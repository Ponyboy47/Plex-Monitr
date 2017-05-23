/*

    Media.swift

    Created By: Jacob Williams
    Description: This file contains the media structures for easy management of downloaded files
    License: MIT License

*/

import Foundation
import PathKit
import Downpour
import SwiftyBeaver
import JSON

// Media related errors
enum MediaError: Error {
    case unsupportedFormat(String)
    case notImplemented
    case sampleMedia
    case alreadyExists(Path)
    case conversionError(String)
    enum DownpourError: Error {
        case missingTVSeason(String)
        case missingTVEpisode(String)
    }
    enum FFProbeError: Error {
        case couldNotGetMetadata(String)
        case couldNotCreateFFProbe(String)
        case streamNotConvertible(to: CodecType, stream: FFProbeStreamProtocol)
    }
    enum VideoError: Error {
        case invalidConfig
        case noStreams
    }
    enum AudioError: Error {
        case invalidConfig
        case noStreams
    }
}

/// Protocol for the common implementation of Media types
protocol Media: class, JSONInitializable, JSONRepresentable {
    /// The path to the media file
    var path: Path { get set }
    /// The path to the original media file (before it was converted). Only set when the original file is not deleted
    var originalPath: Path? { get set }
    /// Used to retrieve basic data from the file
    var downpour: Downpour { get set }

    /// The name of the file in the proper Plex standardized format
    var plexName: String { get }
    /// The plex filename (including it's extension)
    var plexFilename: String { get }
    /// The directory where the media should be placed within plex
    var finalDirectory: Path { get }

    /// Initializer
    init(_ path: Path) throws
    /// Moves the media file to the finalDirectory
    func move(to newDirectory: Path, log: SwiftyBeaver.Type) throws -> Self
    /// Converts the media file to a Plex DirectPlay supported format
    func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws -> Self
    /// Returns whether or not the Media type supports the given format
    static func isSupported(ext: String) -> Bool
    /// Returns whether or not the Media type needs to be converted for Plex
    ///   DirectPlay capabilities to be enabled
    static func needsConversion(file: Path) -> Bool
}

class BaseMedia: Media {
    var path: Path
    var originalPath: Path?
    var downpour: Downpour
    var plexName: String {
        return downpour.title.wordCased
    }
    var plexFilename: String {
        // Return the plexified name + it's extension
        return plexName + "." + (path.extension ?? "")
    }
    var finalDirectory: Path {
        return ""
    }

    required init(_ path: Path) throws {
        // Set the media file's path to the absolute path
        self.path = path.absolute
        // Create the downpour object
        self.downpour = Downpour(fullPath: path.absolute)
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        // Set the media file's path to the absolute path
        path = Path(try json.get("path")).absolute
        // Create the downpour object
        downpour = Downpour(fullPath: path)
    }

    func move(to plexPath: Path, log: SwiftyBeaver.Type) throws -> Self {
        log.verbose("Preparing to move file: \(path.string)")
        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory
        // Create the directory
        if !mediaDirectory.isDirectory {
            log.verbose("Creating the media file's directory: \(mediaDirectory.string)")
            try mediaDirectory.mkpath()
        }

        // Create a path to the location where the file will RIP
        let finalRestingPlace = mediaDirectory + plexFilename

        // Ensure the finalRestingPlace doesn't already exist
        guard !finalRestingPlace.isFile else {
            throw MediaError.alreadyExists(finalRestingPlace)
        }

        log.verbose("Moving media file '\(path.string)' => '\(finalRestingPlace.string)'")
        // Move the file to the correct plex location
        try path.move(finalRestingPlace)
        log.verbose("Successfully moved file to '\(finalRestingPlace.string)'")
        // Change the path now to match
        path = finalRestingPlace
        return self
    }

    func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws -> Self {
        throw MediaError.notImplemented
    }

    class func isSupported(ext: String) -> Bool {
        print("isSupported(ext: String) is not implemented!")
        return false
    }

    class func needsConversion(file: Path) -> Bool {
        print("needsConversion(file: Path) is not implemented!")
        return false
    }

    /// JSONRepresentable protocol requirement
    func encoded() -> JSON {
        return [
            "path": path.string
        ]
    }

    fileprivate struct Output {
        var stdout: String?
        var stderr: String?
        init (_ out: String?, _ err: String?) {
            stdout = out
            stderr = err
        }
    }

    fileprivate func execute(_ comArgs: String...) -> (Int32, Output) {
        guard let command = comArgs.first else {
            return (-1, Output(nil, "Empty command/arguments string"))
        }
        var args: [String] = []
        if comArgs.count > 1 {
            args = Array(comArgs[1..<comArgs.count])
        }
        return execute(command, args)
    }

    fileprivate func execute(_ command: String, _ arguments: [String]) -> (Int32, Output) {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = [command] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe
        task.launch()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8)
        let stderr = String(data: stderrData, encoding: .utf8)
        task.waitUntilExit()
        return (task.terminationStatus, Output(stdout, stderr))
    }
}

extension BaseMedia: Equatable {
    static func ==(lhs: BaseMedia, rhs: BaseMedia) -> Bool {
        return lhs.path == rhs.path || lhs.plexName == rhs.plexName && lhs.finalDirectory == rhs.finalDirectory
    }
}

/// Management for Video files
final class Video: BaseMedia {
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

    override func move(to: Path, log: SwiftyBeaver.Type) throws -> Video {
        return try super.move(to: to, log: log) as! Video
    }

    override func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws -> Video {
        guard let config = conversionConfig as? VideoConversionConfig else {
            throw MediaError.VideoError.invalidConfig
        }
        return try convert(config, log)
    }

    func needToConvert(streams: (FFProbeVideoStreamProtocol, FFProbeAudioStreamProtocol), with config: VideoConversionConfig, log: SwiftyBeaver.Type) throws -> Bool {
        guard let videoStream = streams.0 as? VideoStream else {
            throw MediaError.FFProbeError.streamNotConvertible(to: .video, stream: streams.0)
        }
        guard let audioStream = streams.1 as? AudioStream else {
            throw MediaError.FFProbeError.streamNotConvertible(to: .audio, stream: streams.1)
        }

        log.verbose("Streams:\n\nVideo:\n\(videoStream.description)\n\nAudio:\n\(audioStream.description)")

        let container = VideoContainer(rawValue: self.path.extension ?? "") ?? .other
        guard container == config.container else { return true }

        guard let videoCodec = videoStream.codec as? VideoCodec, config.videoCodec == .any || videoCodec == config.videoCodec else { return true }

        guard let audioCodec = audioStream.codec as? AudioCodec, config.audioCodec == .any || audioCodec == config.audioCodec else { return true }

        guard videoStream.framerate <= config.maxFramerate else { return true }

        return false
    }

    func convert(_ conversionConfig: VideoConversionConfig, _ log: SwiftyBeaver.Type) throws -> Video {
        log.info("Getting audio/video stream data for '\(self.path.absolute)'")

        // Get video file metadata using ffprobe
        let (ffprobeRC, ffprobeOutput) = execute("ffprobe", "-hide_banner", "-of", "json", "-show_streams", "\(path.absolute)")
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
        log.verbose("Got audio/video stream data for '\(self.path.absolute)' => '\(ffprobeStdout)'")

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

        log.info("Got main audio/video streams. Checking if we need to convert file")
        do {
            // Check to see if the main stream needs to be converted
            if try !needToConvert(streams: (mainVideoStream, mainAudioStream), with: conversionConfig, log: log) {
                return self
            }
        } catch {
            log.error("Unable to determine if we need to convert media file! Error occurred => \(error)")
            return self
        }

        log.info("We must convert media file '\(path.absolute)' for Plex Direct Play/Stream!")

        // Build the arguments for the transcode_video command
        var args: [String] = ["--title", "\(mainVideoStream.index)", "--target", "big", "--quick", "--preset", "fast", "--no-log"]

        var outputExtension = "mkv"
        if conversionConfig.container == .mp4 {
            args.append("--mp4")
            outputExtension = "mp4"
        } else if conversionConfig.container == .m4v {
            args.append("--m4v")
            outputExtension = "m4v"
        }

        let ext = path.extension ?? ""
        var manuallyDeleteOriginal = false
        var outputPath: Path

        // This is only set when deleteOriginal is false
        if let tempDir = conversionConfig.tempDir {
            outputPath = tempDir
            args += ["--output", "\(tempDir.absolute)"]
            // If the current container is the same as the output container,
            // rename the original file
            if ext == conversionConfig.container.rawValue {
                let filename = "\(plexName) - original.\(ext)"
                try path.move(path.parent + filename)
            }
        } else {
            // If the output extension is different than the original file's
            // extension then we will have to manually delete the file later
            if ext != conversionConfig.container.rawValue {
                manuallyDeleteOriginal = true
            }
            args += ["--output", "\(path.parent)"]
            outputPath = path.parent
        }
        // We need the full outputPath of the transcoded file so that we can
        // update the path of this media object, and move it to plex if it
        // isn't already there
        outputPath += path.lastComponentWithoutExtension + outputExtension

        // Add the input filepath to the args
        args.append(path.absolute.string)

        let (rc, output) = execute("transcode-video", args)

        guard rc == 0 else {
            var error: String = "Error attempting to transcode: \(path)"
            if let stderr = output.stderr {
                error += "\n\tStandard Error: \(stderr)"
            }
            if let stdout = output.stdout {
                error += "\n\tStandard Out: \(stdout)"
            }
            throw MediaError.conversionError(error)
        }
        log.info("Successfully converted media file '\(path)' to '\(outputPath)'")

        if manuallyDeleteOriginal {
            try path.delete()
            log.info("Successfully deleted original media file '\(path)'")
        } else {
            originalPath = path
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

    override class func needsConversion(file: Path) -> Bool {
        return false
    }
}

/// Management for Audio files
final class Audio: BaseMedia {
    /// The supported extensions
    enum SupportedExtension: String {
        case mp3
        case m4a
        case alac
        case flac
        case aac
        case wav
    }

    override var plexName: String {
        // Audio files are usually pretty simple
        return path.lastComponentWithoutExtension
    }
    override var finalDirectory: Path {
        // Music goes in the Music + Artist + Album directory
        var base: Path = "Music"
        guard let artist = downpour.artist else { return base + "Unknown" }
        base += artist
        guard let album = downpour.album else { return base + "Unknown" }
        base += album
        return base
    }

    required init(_ path: Path) throws {
        guard Audio.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(path.extension ?? "")
        }
        try super.init(path)
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        let p = Path(try json.get("path"))
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Audio.isSupported(ext: p.extension ?? "") else {
            throw MediaError.unsupportedFormat(p.extension ?? "")
        }
        try super.init(json: json)
    }

    override func move(to: Path, log: SwiftyBeaver.Type) throws -> Audio {
        return try super.move(to: to, log: log) as! Audio
    }

    override func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws -> Audio {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable audio (if necessary)
        guard let config = conversionConfig as? AudioConversionConfig else {
            throw MediaError.AudioError.invalidConfig
        }
        return try convert(config, log)
    }

    func convert(_ conversionConfig: AudioConversionConfig, _ log: SwiftyBeaver.Type) throws -> Audio {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable audio (if necessary)
        return self
    }

	override class func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }

    override class func needsConversion(file: Path) -> Bool {
        return false
    }
}

final class Subtitle: BaseMedia {
    enum SupportedExtension: String {
        case srt
        case smi
        case ssa
        case ass
        case vtt
    }

    /// Common subtitle languages to look out for
    private let commonLanguages: [String] = [
                                             "english", "spanish", "portuguese",
                                             "german", "swedish", "russian",
                                             "french", "chinese", "japanese",
                                             "hindu", "persian", "italian",
                                             "greek"
                                            ]

    override var plexFilename: String {
        var name = "\(plexName)."
        if let l = lang {
            name += "\(l)."
        }
        name += path.extension ?? "uft"
        return name
    }
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
        var language: String?
        if let match = path.lastComponent.range(of: "anoXmous_([a-z]{3})", options: .regularExpression) {
            language = path.lastComponent[match].replacingOccurrences(of: "anoXmous_", with: "")
        } else {
            for lang in commonLanguages {
                if path.lastComponent.lowercased().contains(lang) || path.lastComponent.lowercased().contains(".\(lang.substring(to: 3)).") {
                    language = lang.substring(to: 3)
                    break
                }
            }
        }

        if let l = language {
            lang = l
        } else {
            lang = "unknown-\(path.lastComponent)"
        }

        // Return the calulated name
        return name
    }
    var lang: String?
    override var finalDirectory: Path {
        var name = plexName
        while name.contains("unknown") {
            name = Path(name).lastComponentWithoutExtension
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

    required init(_ path: Path) throws {
        try super.init(path)
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Subtitle.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(path.extension ?? "")
        }

        if downpour.type == .tv {
            guard let _ = downpour.season else {
                throw MediaError.DownpourError.missingTVSeason(path.string)
            }
            guard let _ = downpour.episode else {
                throw MediaError.DownpourError.missingTVEpisode(path.string)
            }
        }
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        let p = Path(try json.get("path"))
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Subtitle.isSupported(ext: p.extension ?? "") else {
            throw MediaError.unsupportedFormat(p.extension ?? "")
        }
        try super.init(json: json)

        if downpour.type == .tv {
            guard let _ = downpour.season else {
                throw MediaError.DownpourError.missingTVSeason(p.string)
            }
            guard let _ = downpour.episode else {
                throw MediaError.DownpourError.missingTVEpisode(p.string)
            }
        }
    }

    override func move(to: Path, log: SwiftyBeaver.Type) throws -> Subtitle {
        return try super.move(to: to, log: log) as! Subtitle
    }

    override func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws -> Subtitle {
        // Subtitles don't need to be converted
        return self
    }

    override class func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}

/// Management for media types that we don't care about and can just delete
final class Ignore: BaseMedia {
    enum SupportedExtension: String {
        case txt; case png; case jpg; case jpeg
        case gif; case rst; case md; case nfo
        case sfv; case sub; case idx; case css
        case js; case htm; case html; case url
        case php; case md5; case doc; case docx
        case rtf; case db
    }

    override var plexName: String {
        return path.lastComponentWithoutExtension
    }
    override var finalDirectory: Path {
        return "/dev/null"
    }

    required init(_ path: Path) throws {
        if !path.string.lowercased().contains("sample") && !path.string.lowercased().contains(".ds_store") {
            guard Ignore.isSupported(ext: path.extension ?? "") else {
                throw MediaError.unsupportedFormat(path.extension ?? "")
            }
        }
        try super.init(path)
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        let p = Path(try json.get("path"))
        if !p.string.lowercased().contains("sample") && !p.string.lowercased().contains(".ds_store") {
            guard Ignore.isSupported(ext: p.extension ?? "") else {
                throw MediaError.unsupportedFormat(p.extension ?? "")
            }
        }
        try super.init(json: json)
    }

    override func move(to: Path, log: SwiftyBeaver.Type) throws -> Ignore {
        log.verbose("Deleting ignorable file: \(path.string)")
        try path.delete()
        path = ""
        return self
    }

    override func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws -> Ignore {
        // Ignored files don't need to be converted
        return self
    }

	override class func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}
