/*

 VideoMedia.swift

 Created By: Jacob Williams
 Description: This file contains the Video media structure for easy management of downloaded files
 License: MIT License

 */

import Foundation
import PathKit
import Downpour
import SwiftyBeaver
import SwiftShell

/// Management for Video files
final class Video: ConvertibleMedia, Equatable {
    /// The supported extensions
    static var supportedExtensions: [String] = ["mp4", "mkv", "m4v", "avi",
                                                "wmv", "mpg"]

    var path: Path
    var isHomeMedia: Bool = false
    var downpour: Downpour
    var unconvertedFile: Path?
    var subtitles: [Subtitle]
    var conversionConfig: ConversionConfig?

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
            return Path("Home Videos\(Path.separator)\(plexName)")
        }

        var base: Path
        switch downpour.type {
        case .movie:
            base = Path("Movies\(Path.separator)\(plexName)")
        case .tv:
            base = Path("TV Shows\(Path.separator)\(downpour.title.wordCased)\(Path.separator)Season \(String(format: "%02d", Int(downpour.season!)!))\(Path.separator)\(plexName)")
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

        guard let c = VideoContainer(rawValue: path.extension ?? "") else {
            throw MediaError.unknownContainer(path.extension ?? "")
        }
        container = c

        // Set the media file's path to the absolute path
        self.path = path.absolute
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

    func move(to plexPath: Path, logger: SwiftyBeaver.Type) throws -> MediaState {
        for subtitle in subtitles {
            let subtitleState = try subtitle.move(to: plexPath, logger: logger)
            switch subtitleState {
            case .success:
                continue
            default:
                return .subtitle(subtitleState, subtitle)
            }
        }

        if self.conversionConfig != nil, try self.needsConversion(logger) {
            return .waiting(.converting)
        }

        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory

        // Create a path to the location where the file will RIP
        let finalRestingPlace = mediaDirectory + plexFilename

        guard path.absolute != finalRestingPlace.absolute else {
            logger.info("Media file is already located at it's final resting place")
            return .unconverted(try self.moveUnconverted(to: plexPath, logger: logger))
        }

        logger.verbose("Preparing to move file: \(path.string)")
        // Create the directory
        if !mediaDirectory.isDirectory {
            logger.verbose("Creating the media file's directory: \(mediaDirectory.string)")
            try mediaDirectory.mkpath()
        }

        // Ensure the finalRestingPlace doesn't already exist
        guard !finalRestingPlace.isFile else {
            throw MediaError.alreadyExists(finalRestingPlace)
        }

        logger.verbose("Moving media file '\(path.string)' => '\(finalRestingPlace.string)'")
        // Move the file to the correct plex location
        try path.move(finalRestingPlace)
        logger.verbose("Successfully moved file to '\(finalRestingPlace.string)'")
        // Change the path now to match
        path = finalRestingPlace

        guard path.isFile else {
            logger.error("Successfully moved the file, but there is no file located at the final resting place '\(path.string)'")
            return .failed(.moving, self)
        }

        return .unconverted(try self.moveUnconverted(to: plexPath, logger: logger))
    }

    func deleteSubtitles() throws {
        while subtitles.count > 0 {
            let subtitle = subtitles.removeFirst()
            try subtitle.delete()
        }
    }

    func convert(_ logger: SwiftyBeaver.Type) throws -> MediaState {
        let config = conversionConfig as! VideoConversionConfig

        // Build the arguments for the transcode_video command
        var args: [String] = ["--target", "big", "--quick", "--preset", "fast", "--verbose", "--main-audio", config.mainLanguage.rawValue, "--limit-rate", "\(config.maxFramerate)"]

        if config.subtitleScan {
            args += ["--burn-subtitle", "scan"]
        }

        let outputExtension = config.container.rawValue
        switch config.container {
        case .mp4:
            args.append("--mp4")
        case .m4v:
            args.append("--m4v")
        case .mkv: break
        default:
            throw MediaError.VideoError.unknownContainer(config.container.rawValue)
        }

        let ext = path.extension ?? ""
        var deleteOriginal = false
        var outputPath: Path

        // This is only set when deleteOriginal is false
        if let tempDir = config.tempDir {
            logger.info("Using temporary directory to convert '\(path)'")
            outputPath = tempDir
            // If the current container is the same as the output container,
            // rename the original file
            if ext == outputExtension {
                let filename = "\(plexName) - original.\(ext)"
                logger.info("Input/output extensions are identical, renaming original file from '\(path.lastComponent)' to '\(filename)'")
                try path.rename(filename)
                path = path.parent + filename
            }
        } else {
            deleteOriginal = true
            if ext == outputExtension {
                let filename = "\(plexName) - original.\(ext)"
                logger.info("Input/output extensions are identical, renaming original file from '\(path.lastComponent)' to '\(filename)'")
                try path.rename(filename)
                path = path.parent + filename
            }
            outputPath = path.parent
        }
        // We need the full outputPath of the transcoded file so that we can
        // update the path of this media object, and move it to plex if it
        // isn't already there
        outputPath += "\(Path.separator)\(plexName).\(outputExtension)"

        // Add the input filepath to the args
        args += [path.absolute.string, "--output", outputPath.string]

        logger.info("Beginning conversion of media file '\(path)'")
        let transcodeVideoResponse = SwiftShell.run("transcode-video", args)

        guard transcodeVideoResponse.succeeded else {
            var error: String = "Error attempting to transcode: \(path)"
            error += "\n\tCommand: transcode-video \(args.joined(separator: " "))\n\tResponse: \(transcodeVideoResponse.exitcode)"
            if !transcodeVideoResponse.stdout.isEmpty {
                error += "\n\tStandard Out: \(transcodeVideoResponse.stdout)"
            }
            if !transcodeVideoResponse.stderror.isEmpty {
                error += "\n\tStandard Error: \(transcodeVideoResponse.stderror)"
            }
            throw MediaError.conversionError(error)
        }

        logger.info("Successfully converted media file '\(path)' to '\(outputPath)'")

        if deleteOriginal {
            try path.delete()
            logger.info("Successfully deleted original media file '\(path)'")
        } else {
            unconvertedFile = path
        }

        // Update the media object's path
        path = outputPath

        return .success(.converting)
    }

    func encode(to encoder: Encoder) throws {
        try (self as ConvertibleMedia).encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(subtitles, forKey: .subtitles)
    }

    func needsConversion(_ logger: SwiftyBeaver.Type) throws -> Bool {
        guard let config = conversionConfig as? VideoConversionConfig else {
            throw MediaError.VideoError.invalidConfig
        }
        logger.info("Getting audio/video stream data for '\(path.absolute)'")

        // Get video file metadata using ffprobe (We must escape spaces or this
        // command fails to execute)
        let ffprobeResponse = SwiftShell.run(bash: "ffprobe -hide_banner -of json -show_streams '\(path.absolute.string)'")
        guard ffprobeResponse.succeeded else {
            throw MediaError.FFProbeError.couldNotGetMetadata(ffprobeResponse.stderror)
        }
        guard !ffprobeResponse.stdout.isEmpty else {
            throw MediaError.FFProbeError.couldNotGetMetadata("File does not contain any metadata")
        }
        logger.verbose("Got audio/video stream data for '\(path.absolute)' => '\(ffprobeResponse.stdout)'")

        let ffprobe = try JSONDecoder().decode(FFProbe.self, from: ffprobeResponse.stdout.data(using: .utf8)!)

        var videoStreams = ffprobe.videoStreams
        var audioStreams = ffprobe.audioStreams

        let mainVideoStream: VideoStream
        let mainAudioStream: AudioStream

        // I assume that this will probably never be used since pretty much
        // everything is just gonna have one video stream, but just in case,
        // choose the one with the longest duration since that should be the
        // main feature. If the durations are the same, find the one with the
        // largest dimensions since that should be the highest quality one. If
        // multiple have the same dimensions, find the one with the highest bitrate.
        // If multiple have the same bitrate, see if either has the right codec. If
        // neither has the preferred codec, or they both do, then go for the lowest index
        if videoStreams.count > 1 {
            logger.info("Multiple video streams found, trying to identify the main one...")
            mainVideoStream = videoStreams.reduce(videoStreams[0]) { prevStream, nextStream in
                if let prevDuration = prevStream.duration, let nextDuration = nextStream.duration {
                    if prevDuration > nextDuration {
                        return prevStream
                    }
                } else if prevStream.dimensions! != nextStream.dimensions! {
                    if prevStream.dimensions! > nextStream.dimensions! {
                        return prevStream
                    }
                } else if let prevBitRate = prevStream.bitRate, let nextBitRate = nextStream.bitRate {
                    if prevBitRate > nextBitRate {
                        return prevStream
                    }
                } else if prevStream.codec as! VideoCodec != nextStream.codec as! VideoCodec {
                    if prevStream.codec as! VideoCodec == config.videoCodec {
                        return prevStream
                    } else if nextStream.codec as! VideoCodec != config.videoCodec && prevStream.index < nextStream.index {
                        return prevStream
                    }
                } else if prevStream.index < nextStream.index {
                    return prevStream
                }
                return nextStream
            }
        } else if videoStreams.count == 1 {
            mainVideoStream = videoStreams[0]
        } else {
            throw MediaError.VideoError.noStreams
        }

        // This is much more likely to occur than multiple video streams. So
        // first we'll check to see if the language is the main language set up
        // in the config, then we'll check the bit rates to see which is
        // higher, then we'll check the sample rates, next the codecs, and
        // finally their indexes
        if audioStreams.count > 1 {
            logger.info("Multiple audio streams found, trying to identify the main one...")
            mainAudioStream = audioStreams.reduce(audioStreams[0]) { prevStream, nextStream in
                func followupComparisons(_ pStream: FFProbeAudioStreamProtocol, _ nStream: FFProbeAudioStreamProtocol) -> FFProbeAudioStreamProtocol {
                    if let pBitRate = pStream.bitRate, let nBitRate = nStream.bitRate {
                        if pBitRate > nBitRate {
                            return pStream
                        }
                    } else if pStream.sampleRate != nStream.sampleRate {
                        if pStream.sampleRate! > nStream.sampleRate! {
                            return pStream
                        }
                    } else if pStream.codec as! AudioCodec != nStream.codec as! AudioCodec {
                        if pStream.codec as! AudioCodec == config.audioCodec {
                            return pStream
                        } else if nStream.codec as! AudioCodec != config.audioCodec && pStream.index < nStream.index {
                            return pStream
                        }
                    } else if pStream.index < nStream.index {
                        return pStream
                    }
                    return nStream
                }
                if prevStream.language != nextStream.language {
                    let pLang = prevStream.language
                    let nLang = nextStream.language
                    if pLang == config.mainLanguage {
                        return prevStream
                    } else if nLang != config.mainLanguage {
                        return followupComparisons(prevStream, nextStream) as! AudioStream
                    }
                } else {
                    return followupComparisons(prevStream, nextStream) as! AudioStream
                }
                return nextStream
            }
        } else if audioStreams.count == 1 {
            mainAudioStream = audioStreams[0]
        } else {
            throw MediaError.AudioError.noStreams
        }

        logger.info("Got main audio/video streams. Checking if we need to convert them")
        return try needToConvert(videoStream: mainVideoStream, audioStream: mainAudioStream, logger: logger)
    }

    private func needToConvert(videoStream: VideoStream, audioStream: AudioStream, logger: SwiftyBeaver.Type) throws -> Bool {
        guard let config = conversionConfig as? VideoConversionConfig else {
            throw MediaError.VideoError.invalidConfig
        }

        logger.verbose("Streams:\n\nVideo:\n\(videoStream.description)\n\nAudio:\n\(audioStream.description)")

        guard let container = VideoContainer(rawValue: path.extension ?? "") else {
            throw MediaError.unknownContainer(path.extension ?? "")
        }
        guard container == config.container else { return true }

        guard let videoCodec = videoStream.codec as? VideoCodec, config.videoCodec == .any || videoCodec == config.videoCodec else { return true }

        guard let audioCodec = audioStream.codec as? AudioCodec, config.audioCodec == .any || audioCodec == config.audioCodec else { return true }

        guard videoStream.framerate!.value <= config.maxFramerate else { return true }

        return false
    }

    func findSubtitles(below: Path, logger: SwiftyBeaver.Type) {
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
            logger.warning("Failed to get children when trying to find a video file's subtitles")
            logger.error(error)
        }
    }

    static func == (lhs: Video, rhs: Video) -> Bool {
        return lhs.path == rhs.path
    }
    static func == <T: Media>(lhs: Video, rhs: T) -> Bool {
        return lhs.path == rhs.path
    }
    static func == <T: Media>(lhs: T, rhs: Video) -> Bool {
        return lhs.path == rhs.path
    }
}
