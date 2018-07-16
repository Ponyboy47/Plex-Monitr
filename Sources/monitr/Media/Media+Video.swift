/*

 VideoMedia.swift

 Created By: Jacob Williams
 Description: This file contains the Video media structure for easy management of downloaded files
 License: MIT License

 */

import Foundation
import PathKit
import Downpour
import SwiftShell

// swiftlint:disable type_body_length

/// Management for Video files
final class Video: ConvertibleMedia {
    /// The supported extensions
    static var supportedExtensions: [String] = ["mp4", "mkv", "m4v", "avi",
                                                "wmv", "mpg"]

    var path: Path
    var isHomeMedia: Bool = false
    var downpour: Downpour
    var unconvertedFile: Path?
    var subtitles: [Subtitle]
    var conversionConfig: ConversionConfig!
    lazy var videoConversionConfig: VideoConversionConfig? = {
        conversionConfig as? VideoConversionConfig
    }()
    var beenConverted: Bool = false
    weak var mainMonitr: MainMonitr!
    // swiftlint:disable identifier_name
    var _info: FFProbe?
    // swiftlint:enable identifier_name

    var plexName: String {
        guard !isHomeMedia else {
            return path.lastComponentWithoutExtension
        }
        var name: String
        switch downpour.type {
        // If it's a movie file, plex wants "Title (YYYY)"
        case .movie:
            name = "\(downpour.title.wordCased)"
            if let year = downpour.year {
                name += " (\(year))"
            }
        // If it's a tv show, plex wants "Title - sXXeYY"
        case .tv:
            name = "\(downpour.title.wordCased) - s\(String(format: "%02d", Int(downpour.season!)!))e\(String(format: "%02d", Int(downpour.episode!)!))"
        // Otherwise just return the title (shouldn't ever actually reach this)
        default:
            name = downpour.title.wordCased
        }
        // Return the calulated name
        return name
    }
    var finalDirectory: Path {
        guard !isHomeMedia else {
            return Path("Home Videos")
        }

        var base: Path
        switch downpour.type {
        case .movie:
            base = Path("Movies")
        case .tv:
            base = Path("TV Shows\(Path.separator)\(downpour.title.wordCased)\(Path.separator)Season \(String(format: "%02d", Int(downpour.season!)!))")
        default:
            base = ""
        }
        return base
    }

    var container: VideoContainer

    init(_ path: Path) throws {
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Video.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(path.extension ?? "")
        }
        guard !path.string.lowercased().contains("sample") else {
            throw MediaError.VideoError.sampleMedia
        }

        // swiftlint:disable identifier_name
        guard let c = VideoContainer(rawValue: path.extension ?? "") else {
            throw MediaError.unknownContainer(path.extension ?? "")
        }
        container = c
        // swiftlint:enable identifier_name

        // Set the media file's path to the absolute path
        self.path = path.absolute
        self.unconvertedFile = path.absolute
        // Create the downpour object
        self.downpour = Downpour(fullPath: path.absolute)

        self.subtitles = []

        if self.downpour.type == .tv {
            guard self.downpour.season != nil else {
                throw MediaError.DownpourError.missingTVSeason(self.path.string)
            }
            guard self.downpour.episode != nil else {
                throw MediaError.DownpourError.missingTVEpisode(self.path.string)
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case path
        case isHomeMedia
        case unconvertedFile
        case subtitles
    }

    convenience init(from decoder: Decoder) throws {
        try self.init(from: decoder)

        let values = try decoder.container(keyedBy: CodingKeys.self)

        subtitles = try values.decode([Subtitle].self, forKey: .subtitles)
        for subtitle in subtitles {
            subtitle.linkedVideo = self
        }
    }

    func move(to plexPath: Path) throws -> MediaState {
        for subtitle in subtitles {
            let subtitleState = try subtitle.move(to: plexPath)
            switch subtitleState {
            case .success:
                continue
            default:
                return .subtitle(subtitleState, subtitle)
            }
        }

        // If we aren't configured to convert or don't need to convert, then
        // just move the file like normal
        return try commonMove(to: plexPath)
    }

    func deleteSubtitles() throws {
        while subtitles.count > 0 {
            let subtitle = subtitles.removeFirst()
            try subtitle.delete()
        }
    }

    func buildArgs(_ config: VideoConversionConfig) -> [String] {
        var args: [String] = ["--handbrake-option", "optimize", "--verbose", "--main-audio", config.mainLanguage.rawValue, "--limit-rate", "\(config.maxFramerate)"]

        for target in config.targets {
            switch target.rawValue {
            case .size(let size): args += ["--target", "\(size)"]
            case .bitRate(let profile, let bitRate): args += ["--target", "\(profile)=\(bitRate)"]
            }
        }

        if config.abr {
            args.append("--abr")
        }
        if config.h265 {
            args += ["--handbrake-option", "encoder=x265"]
        }
        if config.speed != .`default` {
            args.append("--\(config.speed)")
        }
        if config.x264Preset != .`default` {
            args.append("--\(config.x264Preset)")
        }
        if config.subtitleScan {
            args += ["--burn-subtitle", "scan"]
        }

        switch config.videoContainer {
        case .mp4:
            args.append("--mp4")
        case .m4v:
            args.append("--m4v")
        default: break
        }

        return args
    }

    func convertCommand() throws -> Command {
        guard let config = videoConversionConfig else {
            throw MediaError.VideoError.invalidConfig
        }

        var args = buildArgs(config)

        let ext = path.extension ?? ""
        var outputPath: Path = config.tempDir

        let filename = "\(plexName) - original.\(ext)"
        if !(path.parent + filename).exists {
            try path.rename(filename)
            loggerQueue.async {
                logger.debug("Renamed file from '\(self.path)' to '\(self.path.parent + filename)'")
            }
            path = path.parent + filename
        }

        // We need the full outputPath of the transcoded file so that we can
        // update the path of this media object, and move it to plex if it
        // isn't already there
        outputPath += "\(Path.separator)\(plexName).\(config.videoContainer.rawValue)"

        // Add the input filepath to the args
        args += [path.absolute.string, "--output", outputPath.string]

        return ("transcode-video", args, outputPath, config.deleteOriginal)
    }

    func encode(to encoder: Encoder) throws {
        try (self as ConvertibleMedia).encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(subtitles, forKey: .subtitles)
    }

    func needsConversion() throws -> Bool {
        guard let config = videoConversionConfig else {
            throw MediaError.VideoError.invalidConfig
        }
        loggerQueue.async {
            logger.verbose("Getting audio/video stream data for '\(self.path.absolute)'")
        }

        let ffprobe = try info()

        var videoStreams = ffprobe.videoStreams
        var audioStreams = ffprobe.audioStreams

        let mainVideoStream: VideoStream
        let mainAudioStream: AudioStream

        if videoStreams.count > 1 {
            loggerQueue.async {
                logger.warning("Multiple video streams found, trying to identify the main one...")
            }
            mainVideoStream = identifyMainVideoStream(videoStreams, using: config)
        } else if videoStreams.count == 1 {
            mainVideoStream = videoStreams[0]
        } else {
            throw MediaError.VideoError.noStreams
        }

        if audioStreams.count > 1 {
            loggerQueue.async {
                logger.warning("Multiple audio streams found, trying to identify the main one...")
            }
            mainAudioStream = identifyMainAudioStream(audioStreams, using: config)
        } else if audioStreams.count == 1 {
            mainAudioStream = audioStreams[0]
        } else {
            throw MediaError.AudioError.noStreams
        }

        loggerQueue.async {
            logger.verbose("Got main audio/video streams. Checking if we need to convert them")
        }
        return try needToConvert(videoStream: mainVideoStream, audioStream: mainAudioStream)
    }

    // I assume that this will probably never be used since pretty much
    // everything is just gonna have one video stream, but just in case,
    // choose the one with the longest duration since that should be the
    // main feature. If the durations are the same, find the one with the
    // largest dimensions since that should be the highest quality one. If
    // multiple have the same dimensions, find the one with the highest bitrate.
    // If multiple have the same bitrate, see if either has the right codec. If
    // neither has the preferred codec, or they both do, then go for the lowest index
    private func identifyMainVideoStream(_ videoStreams: [VideoStream], using config: VideoConversionConfig) -> VideoStream {
        return videoStreams.reduce(videoStreams[0]) { mainStream, nextStream in
            if mainStream.duration > nextStream.duration {
                return mainStream
            } else if mainStream.dimensions! > nextStream.dimensions! {
                return mainStream
            } else if mainStream.bitRate > nextStream.bitRate {
                return mainStream
            } else if mainStream.codec as? VideoCodec != nextStream.codec as? VideoCodec {
                if mainStream.codec as? VideoCodec == config.videoCodec {
                    return mainStream
                } else if nextStream.codec as? VideoCodec != config.videoCodec && mainStream.index < nextStream.index {
                    return mainStream
                }
            } else if mainStream.index < nextStream.index {
                return mainStream
            }
            return nextStream
        }
    }

    // This is much more likely to occur than multiple video streams. So
    // first we'll check to see if the language is the main language set up
    // in the config, then we'll check the bit rates to see which is
    // higher, then we'll check the sample rates, next the codecs, and
    // finally their indexes
    private func identifyMainAudioStream(_ audioStreams: [AudioStream], using config: VideoConversionConfig) -> AudioStream {
        return audioStreams.reduce(audioStreams[0]) { mainStream, nextStream in
            if mainStream.language != nextStream.language {
                if mainStream.language == config.mainLanguage {
                    return mainStream
                }
            } else if mainStream.channels > nextStream.channels {
                return mainStream
            } else if mainStream.channelLayout > nextStream.channelLayout {
                return mainStream
            } else if mainStream.bitRate > nextStream.bitRate {
                return mainStream
            } else if mainStream.sampleRate > nextStream.sampleRate {
                return mainStream
            } else if mainStream.codec as? AudioCodec != nextStream.codec as? AudioCodec {
                if mainStream.codec as? AudioCodec == config.audioCodec {
                    return mainStream
                } else if nextStream.codec as? AudioCodec != config.audioCodec && mainStream.index < nextStream.index {
                    return mainStream
                }
            } else if mainStream.index < nextStream.index {
                return mainStream
            }
            return nextStream
        }
    }

    private func needToConvert(videoStream: VideoStream, audioStream: AudioStream) throws -> Bool {
        guard let config = videoConversionConfig else {
            throw MediaError.VideoError.invalidConfig
        }

        loggerQueue.async {
            logger.verbose("Streams:\n\nVideo:\n\(videoStream.description)\n\nAudio:\n\(audioStream.description)")
        }

        guard let container = VideoContainer(rawValue: path.extension ?? "") else {
            throw MediaError.unknownContainer(path.extension ?? "")
        }

        guard container == config.videoContainer else { return true }

        guard let videoCodec = videoStream.codec as? VideoCodec, config.videoCodec == .any || videoCodec == config.videoCodec else { return true }

        guard let audioCodec = audioStream.codec as? AudioCodec, config.audioCodec == .any || audioCodec == config.audioCodec else { return true }

        guard videoStream.framerate!.value <= config.maxFramerate else { return true }

        loggerQueue.async {
            logger.verbose("\(self.path) does not need to be converted")
        }
        return false
    }

    func findSubtitles(below: Path) {
        // Get the highest directory that is below the below Path
        var top = path
        // If we don't do the absolute paths, then the string comparison on the
        // paths won't work properly
        while top.parent.absolute != below.absolute {
            top = top.parent
        }
        // This occurs when the from Path is in the below Path and so the above
        // while loop never gets from's parent directory
        if !top.isDirectory {
            top = top.parent
        }
        do {
            // Go through the children in the top directory and find all
            // possible subtitle files
            let children: [Path] = try top == below ? top.children() : top.recursiveChildren()
            for childFile in children where childFile.isFile {
                let ext = childFile.extension ?? ""
                do {
                    if Subtitle.isSupported(ext: ext) {
                        let subtitle = try Subtitle(childFile)
                        subtitle.linkedVideo = self
                        subtitles.append(subtitle)
                    }
                } catch {
                    continue
                }
            }
        } catch {
            loggerQueue.async {
                logger.error("Failed to get children when trying to find a video file's subtitles")
                logger.debug(error)
            }
        }
    }
}

fileprivate extension Optional where Wrapped: Comparable {
    static func > (lhs: Wrapped?, rhs: Wrapped?) -> Bool {
        if let left = lhs, let right = rhs {
            return left > right
        }
        return false
    }
}
