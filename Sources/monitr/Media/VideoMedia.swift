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
import JSON

/// Management for Video files
final class Video: BaseConvertibleMedia {
    /// The supported extensions
    enum SupportedExtension: String {
        case mp4
        case mkv
        case m4v
        case avi
        case wmv
    }

    // Lazy vars so these are calculated only once

    override var plexName: String {
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
    override var finalDirectory: Path {
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

    required init(_ path: Path) throws {
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Video.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(path.extension ?? "")
        }
        guard !path.string.lowercased().contains("sample") else {
            throw MediaError.sampleMedia
        }

        if let c = VideoContainer(rawValue: path.extension ?? "") {
            container = c
        } else {
            container = .other
        }

        try super.init(path)

        if self.downpour.type == .tv {
            guard let _ = self.downpour.season else {
                throw MediaError.DownpourError.missingTVSeason(self.path.string)
            }
            guard let _ = self.downpour.episode else {
                throw MediaError.DownpourError.missingTVEpisode(self.path.string)
            }
        }
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        let p = Path(try json.get("path"))
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Video.isSupported(ext: p.extension ?? "") else {
            throw MediaError.unsupportedFormat(p.extension ?? "")
        }
        guard !p.string.lowercased().contains("sample") else {
            throw MediaError.sampleMedia
        }

        if let c = VideoContainer(rawValue: p.extension ?? "") {
            container = c
        } else {
            container = .other
        }

        try super.init(json: json)

        if self.downpour.type == .tv {
            guard let _ = self.downpour.season else {
                throw MediaError.DownpourError.missingTVSeason(p.string)
            }
            guard let _ = self.downpour.episode else {
                throw MediaError.DownpourError.missingTVEpisode(p.string)
            }
        }
    }

    override func move(to plexPath: Path, log: SwiftyBeaver.Type) throws -> Video {
        return try super.move(to: plexPath, log: log) as! Video
    }

    override func moveUnconverted(to plexPath: Path, log: SwiftyBeaver.Type) throws -> Video {
        return try super.moveUnconverted(to: plexPath, log: log) as! Video
    }

    override func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws -> Video {
        guard let config = conversionConfig as? VideoConversionConfig else {
            throw MediaError.VideoError.invalidConfig
        }
        return try convert(config, log)
    }

    func convert(_ conversionConfig: VideoConversionConfig, _ log: SwiftyBeaver.Type) throws -> Video {
        // Build the arguments for the transcode_video command
        var args: [String] = ["--target", "big", "--quick", "--preset", "fast", "--verbose", "--main-audio", conversionConfig.mainLanguage.rawValue, "--limit-rate", "\(conversionConfig.maxFramerate)"]

        if conversionConfig.subtitleScan {
            args += ["--burn-subtitle", "scan"]
        }

        var outputExtension = "mkv"
        if conversionConfig.container == .mp4 {
            args.append("--mp4")
            outputExtension = "mp4"
        } else if conversionConfig.container == .m4v {
            args.append("--m4v")
            outputExtension = "m4v"
        }

        let ext = path.extension ?? ""
        var deleteOriginal = false
        var outputPath: Path

        // This is only set when deleteOriginal is false
        if let tempDir = conversionConfig.tempDir {
            log.info("Using temporary directory to convert '\(path)'")
            outputPath = tempDir
            // If the current container is the same as the output container,
            // rename the original file
            if ext == outputExtension {
                let filename = "\(plexName) - original.\(ext)"
                log.info("Input/output extensions are identical, renaming original file from '\(path.lastComponent)' to '\(filename)'")
                try path.rename(filename)
                path = path.parent + filename
            }
        } else {
            deleteOriginal = true
            if ext == outputExtension {
                let filename = "\(plexName) - original.\(ext)"
                log.info("Input/output extensions are identical, renaming original file from '\(path.lastComponent)' to '\(filename)'")
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

        log.info("Beginning conversion of media file '\(path)'")
        let (rc, output) = Video.execute("transcode-video", args)

        guard rc == 0 else {
            var error: String = "Error attempting to transcode: \(path)"
            error += "\n\tCommand: transcode-video \(args.joined(separator: " "))"
            if let stderr = output.stderr, !stderr.isEmpty {
                error += "\n\tStandard Error: \(stderr)"
            }
            if let stdout = output.stdout, !stdout.isEmpty {
                error += "\n\tStandard Out: \(stdout)"
            }
            throw MediaError.conversionError(error)
        }
        if let stdout = output.stdout, !stdout.isEmpty {
            log.verbose("transcode-video output:\n\n\(stdout)\n\n")
        }

        log.info("Successfully converted media file '\(path)' to '\(outputPath)'")

        if deleteOriginal {
            try path.delete()
            log.info("Successfully deleted original media file '\(path)'")
        } else {
            unconvertedFile = path
        }

        // Update the media object's path
        path = outputPath

        // If the converted file location is not already in the plexDirectory
        if !path.string.contains(finalDirectory.string) {
            return try move(to: conversionConfig.plexDir, log: log)
        }

        return self
    }

    override class func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
    
    override class func needsConversion(file: Path, with config: ConversionConfig, log: SwiftyBeaver.Type) throws -> Bool {
        guard let conversionConfig = config as? VideoConversionConfig else {
            throw MediaError.VideoError.invalidConfig
        }
        log.info("Getting audio/video stream data for '\(file.absolute)'")

        // Get video file metadata using ffprobe
        let (ffprobeRC, ffprobeOutput) = Video.execute("ffprobe", "-hide_banner", "-of", "json", "-show_streams", file.absolute.string)
        guard ffprobeRC == 0 else {
            var err: String = ""
            if let stderr = ffprobeOutput.stderr {
                err = stderr
            }
            throw MediaError.FFProbeError.couldNotGetMetadata(err)
        }
        guard let ffprobeStdout = ffprobeOutput.stdout else {
            throw MediaError.FFProbeError.couldNotGetMetadata("File does not contain any metadata")
        }
        log.verbose("Got audio/video stream data for '\(file.absolute)' => '\(ffprobeStdout)'")

        var ffprobe: FFProbe
        do {
            ffprobe = try FFProbe(ffprobeStdout)
        } catch {
            throw MediaError.FFProbeError.couldNotCreateFFProbe("Failed creating the FFProbe from stdout of the ffprobe command => \(error)")
        }

        var videoStreams = ffprobe.videoStreams
        var audioStreams = ffprobe.audioStreams

        var mainVideoStream: FFProbeVideoStreamProtocol
        var mainAudioStream: FFProbeAudioStreamProtocol

        // I assume that this will probably never be used since pretty much
        // everything is just gonna have one video stream, but just in case,
        // choose the one with the longest duration since that should be the
        // main feature. If the durations are the same, find the one with the
        // largest dimensions since that should be the highest quality one. If
        // multiple have the same dimensions, find the one with the highest bitrate.
        // If multiple have the same bitrate, see if either has the right codec. If
        // neither has the preferred codec, or they both do, then go for the lowest index
        if videoStreams.count > 1 {
            log.info("Multiple video streams found, trying to identify the main one...")
            mainVideoStream = videoStreams.reduce(videoStreams[0]) { prevStream, nextStream in
                if prevStream.duration != nextStream.duration {
                    if prevStream.duration > nextStream.duration {
                        return prevStream
                    }
                } else if prevStream.dimensions != nextStream.dimensions {
                    if prevStream.dimensions > nextStream.dimensions {
                        return prevStream
                    }
                } else if prevStream.bitRate != nextStream.bitRate {
                    if prevStream.bitRate > nextStream.bitRate {
                        return prevStream
                    }
                } else if prevStream.codec as! VideoCodec != nextStream.codec as! VideoCodec {
                    if prevStream.codec as! VideoCodec == conversionConfig.videoCodec {
                        return prevStream
                    } else if nextStream.codec as! VideoCodec != conversionConfig.videoCodec && prevStream.index < nextStream.index {
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
            log.info("Multiple audio streams found, trying to identify the main one...")
            mainAudioStream = audioStreams.reduce(audioStreams[0]) { prevStream, nextStream in
                func followupComparisons(_ pStream: FFProbeAudioStreamProtocol, _ nStream: FFProbeAudioStreamProtocol) -> FFProbeAudioStreamProtocol {
                    if pStream.bitRate != nStream.bitRate {
                        if pStream.bitRate > nStream.bitRate {
                            return pStream
                        }
                    } else if pStream.sampleRate != nStream.sampleRate {
                        if pStream.sampleRate > nStream.sampleRate {
                            return pStream
                        }
                    } else if pStream.codec as! AudioCodec != nStream.codec as! AudioCodec {
                        if pStream.codec as! AudioCodec == conversionConfig.audioCodec {
                            return pStream
                        } else if nStream.codec as! AudioCodec != conversionConfig.audioCodec && pStream.index < nStream.index {
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
                    if pLang == conversionConfig.mainLanguage {
                        return prevStream
                    } else if nLang != conversionConfig.mainLanguage {
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

        log.info("Got main audio/video streams. Checking if we need to convert them")
        return try needToConvert(file: file, streams: (mainVideoStream, mainAudioStream), with: conversionConfig, log: log)
    }

    private class func needToConvert(file: Path, streams: (FFProbeVideoStreamProtocol, FFProbeAudioStreamProtocol), with config: VideoConversionConfig, log: SwiftyBeaver.Type) throws -> Bool {
        guard let videoStream = streams.0 as? VideoStream else {
            throw MediaError.FFProbeError.streamNotConvertible(to: .video, stream: streams.0)
        }
        guard let audioStream = streams.1 as? AudioStream else {
            throw MediaError.FFProbeError.streamNotConvertible(to: .audio, stream: streams.1)
        }

        log.verbose("Streams:\n\nVideo:\n\(videoStream.description)\n\nAudio:\n\(audioStream.description)")

        let container = VideoContainer(rawValue: file.extension ?? "") ?? .other
        guard container == config.container else { return true }

        guard let videoCodec = videoStream.codec as? VideoCodec, config.videoCodec == .any || videoCodec == config.videoCodec else { return true }

        guard let audioCodec = audioStream.codec as? AudioCodec, config.audioCodec == .any || audioCodec == config.audioCodec else { return true }

        guard videoStream.framerate <= config.maxFramerate else { return true }
        
        return false
    }
}
