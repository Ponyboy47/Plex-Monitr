/*

    Config.swift

    Created By: Jacob Williams
    Description: This file contains the Config structure for the Monitr class
    License: MIT License

*/

import Foundation
import PathKit
import JSON
import SwiftyBeaver
import Cron

enum ConfigError: Error {
    case pathIsNotDirectory(Path)
    case pathDoesNotExist(Path)
    case invalidCronString(String)
}

struct Config {
    /// Where the config file should be saved (if the save flag was set to true)
    var configFile: Path = "~/.config/monitr/settings.json"
    /// The directory where the plex Libraries reside
    var plexDirectory: Path = "/var/lib/plexmediaserver/Library"
    /// Where new media is going to be downloaded
    private var _downloadDirectories: [Path] = ["/var/lib/deluge/Downloads"]
    var downloadDirectories: [Path] {
        set {
            // When this is set, update the DirectoryMonitor
            _downloadDirectories = newValue
            downloadWatchers = []
            newValue.forEach { d in
                downloadWatchers.append(DirectoryMonitor(URL: d.url))
            }
        }
        get {
            return _downloadDirectories
        }
    }
    /// Where new home media is going to be downloaded
    private var _homeVideoDownloadDirectories: [Path] = ["~/HomeVideos"]
    var homeVideoDownloadDirectories: [Path] {
        set {
            // When this is set, update the DirectoryMonitor
            _homeVideoDownloadDirectories = newValue
            homeVideoDownloadWatchers = []
            newValue.forEach { d in
                homeVideoDownloadWatchers.append(DirectoryMonitor(URL: d.url))
            }
        }
        get {
            return _homeVideoDownloadDirectories
        }
    }
    /// Whether the media should be converted to Plex DirectPlay formats automatically
    var convert: Bool = false
    /// Whether media should be converted immediately, or during a configurable time when the server is less likely to be busy
    var convertImmediately: Bool = true
    /// The Cron string describing when scheduled media conversions may begin
    var convertCronStart: DatePattern = try! DatePattern("0 0 * * *")
    /// The Cron string describing when scheduled media conversions should be finished
    var convertCronEnd: DatePattern = try! DatePattern("0 8 * * *")
    /// The number of simultaneous threads to convert media on
    var convertThreads: Int = 2
    /// Whether the original media file should be deleted after a successful conversion
    var deleteOriginal: Bool = true
    /// The container to use when converting video media files
    var convertVideoContainer: VideoContainer = .mp4
    /// The video encoding to use when converting media files
    var convertVideoCodec: VideoCodec = .h264
    /// The container to use when converting audio media files
    var convertAudioContainer: AudioContainer = .aac
    /// The audio encoding to use when converting media files
    var convertAudioCodec: AudioCodec = .aac
    /// Whether or not to try and scan media for forcfully burned in subtitle files
    var convertVideoSubtitleScan: Bool = false
    /// The default language to use as the main language for converted media files
    var convertLanguage: Language = .eng
    /// The maximum framerate allowed for video files
    var convertVideoMaxFramerate: Double = 30.0
    /// The directory to place converted media before moving it to Plex
    var convertTempDirectory: Path = "/tmp"
    /// Whether external subtitle files should be deleted upon import with Monitr
    var deleteSubtitles: Bool = false

    var logFile: Path?
    var logLevel: Int = 0
    var log: SwiftyBeaver.Type

    /// Watches the download directory for new files
    private var downloadWatchers: [DirectoryMonitor?] = []
    /// Watches the home video download directory for new files
    private var homeVideoDownloadWatchers: [DirectoryMonitor?] = []

    init(_ configFile: Path? = nil, _ plexDirectory: Path? = nil, _ downloadDirectories: [Path]? = nil,
         _ convert: Bool? = nil, _ convertImmediately: Bool? = nil, _ convertCronStart: DatePattern? = nil,
         _ convertCronEnd: DatePattern? = nil, _ convertThreads: Int? = nil, _ deleteOriginal: Bool? = nil,
         _ convertVideoContainer: VideoContainer? = nil, _ convertVideoCodec: VideoCodec? = nil,
         _ convertAudioContainer: AudioContainer? = nil, _ convertAudioCodec: AudioCodec? = nil,
         _ convertVideoSubtitleScan: Bool? = nil, _ convertLanguage: Language? = nil,
         _ convertVideoMaxFramerate: Double? = nil, _ convertTempDirectory: Path? = nil,
         _ deleteSubtitles: Bool? = nil, _ homeVideoDownloadDirectories: [Path]? = nil,
         _ logLevel: Int? = nil, _ logFile: Path? = nil, logger: SwiftyBeaver.Type) throws {
        self.log = logger
        self.configFile = configFile ?? self.configFile
        self.plexDirectory = plexDirectory ?? self.plexDirectory
        self.downloadDirectories = downloadDirectories ?? self._downloadDirectories
        self.convert = convert ?? self.convert
        self.convertImmediately = convertImmediately ?? self.convertImmediately
        self.convertCronStart = convertCronStart ?? self.convertCronStart
        self.convertCronEnd = convertCronEnd ?? self.convertCronEnd
        self.convertThreads = convertThreads ?? self.convertThreads
        self.deleteOriginal = deleteOriginal ?? self.deleteOriginal
        self.convertVideoContainer = convertVideoContainer ?? self.convertVideoContainer
        self.convertVideoCodec = convertVideoCodec ?? self.convertVideoCodec
        self.convertAudioContainer = convertAudioContainer ?? self.convertAudioContainer
        self.convertAudioCodec = convertAudioCodec ?? self.convertAudioCodec
        self.convertVideoSubtitleScan = convertVideoSubtitleScan ?? self.convertVideoSubtitleScan
        self.convertLanguage = convertLanguage ?? self.convertLanguage
        self.convertVideoMaxFramerate = convertVideoMaxFramerate ?? self.convertVideoMaxFramerate
        self.convertTempDirectory = convertTempDirectory ?? self.convertTempDirectory
        self.deleteSubtitles = deleteSubtitles ?? self.deleteSubtitles
        self.homeVideoDownloadDirectories = homeVideoDownloadDirectories ?? self._homeVideoDownloadDirectories
        self.logLevel = logLevel ?? self.logLevel
        self.logFile = logFile

        // Caps logLevel to the maximum/minimum level
        if self.logLevel > 4 {
            self.logLevel = 4
        } else if self.logLevel < 0 {
            self.logLevel = 0
        }

        // Verify the plex, download, and conversion temp directories exist and are in fact, directories

        if !self.plexDirectory.exists {
            try self.plexDirectory.mkpath()
        }
        guard self.plexDirectory.exists else {
            throw ConfigError.pathDoesNotExist(self.plexDirectory)
        }
        guard self.plexDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory(self.plexDirectory)
        }

        for d in self.downloadDirectories + self.homeVideoDownloadDirectories {
            if !d.exists {
                try d.mkpath()
            }
            guard d.exists else {
                throw ConfigError.pathDoesNotExist(d)
            }
            guard d.isDirectory else {
                throw ConfigError.pathIsNotDirectory(d)
            }
        }

        if self.convert {
            if !self.convertTempDirectory.exists {
                try self.convertTempDirectory.mkpath()
            }
            guard self.convertTempDirectory.exists else {
                throw ConfigError.pathDoesNotExist(self.convertTempDirectory)
            }
            guard self.convertTempDirectory.isDirectory else {
                throw ConfigError.pathIsNotDirectory(self.convertTempDirectory)
            }
        }
    }

    /// Starts monitoring the downloads directory for changes
    @discardableResult
    func startMonitoring() -> Bool {
        for watcher in self.downloadWatchers + self.homeVideoDownloadWatchers {
            do {
                try watcher?.startMonitoring()
            } catch {
                log.warning("Failed to start the directory watcher for '\(String(describing: watcher?.URL.path))'.")
                log.error(error)
                return false
            }
        }
        return true
    }

    /// Stops monitoring the downloads directories
    func stopMonitoring() {
        for watcher in self.downloadWatchers + self.homeVideoDownloadWatchers {
            watcher?.stopMonitoring()
        }
    }

    /// Sets the delegate of the download watchers
    func setDelegate(_ delegate: DirectoryMonitorDelegate) {
        for watcher in self.downloadWatchers + self.homeVideoDownloadWatchers {
            watcher?.delegate = delegate
        }
    }
}

/// Allows the config to be initialized from a json file
extension Config: JSONConvertible {
    /// Initializes by reading the file at the path as a JSON string
    init(_ path: Path, logger: SwiftyBeaver.Type) throws {
        try self.init(path.read())
        configFile = path
        log = logger
    }

    /// Initialize by reading the string as JSON
    init(_ str: String) throws {
        try self.init(json: JSON.Parser.parse(str))
    }

    /// Initialize the config from a JSON object
    init(json: JSON) throws {
        log = SwiftyBeaver.self

        self.plexDirectory = Path((try? json.get("plexDirectory")) ?? self.plexDirectory.string)
        var downloads: [String] = (try? json.get("downloadDirectories")) ?? []
        if let downloadDir: String = try? json.get("downloadDirectory") {
            downloads.append(downloadDir)
        }
        if downloads.isEmpty {
            downloads = self.downloadDirectories.map { $0.string }
        }
        self.downloadDirectories = downloads.map { Path($0) }

        var homeDownloads: [String] = (try? json.get("homeVideoDownloadDirectories")) ?? []
        if homeDownloads.isEmpty {
            homeDownloads = self.homeVideoDownloadDirectories.map { $0.string }
        }
        self.homeVideoDownloadDirectories = homeDownloads.map { Path($0) }

        self.convertTempDirectory = Path((try? json.get("convertTempDirectory")) ?? self.convertTempDirectory.string)
        self.convert = (try? json.get("convert")) ?? self.convert
        self.convertImmediately = (try? json.get("convertImmediately")) ?? self.convertImmediately
        self.convertCronStart = (try? DatePattern(json.get("convertCronStart"))) ?? self.convertCronStart
        self.convertCronEnd = (try? DatePattern(json.get("convertCronEnd"))) ?? self.convertCronEnd
        self.convertThreads = (try? json.get("convertThreads")) ?? self.convertThreads
        self.deleteOriginal = (try? json.get("deleteOriginal")) ?? self.deleteOriginal
        let videoContainerString = (try? json.get("convertVideoContainer")) ?? ""
        self.convertVideoContainer = VideoContainer(rawValue: videoContainerString) ?? self.convertVideoContainer
        let videoCodecString = (try? json.get("convertVideoCodec")) ?? ""
        self.convertVideoCodec = VideoCodec(rawValue: videoCodecString) ?? self.convertVideoCodec
        let audioContainerString = (try? json.get("convertAudioContainer")) ?? ""
        self.convertAudioContainer = AudioContainer(rawValue: audioContainerString) ?? self.convertAudioContainer
        let audioCodecString = (try? json.get("convertAudioCodec")) ?? ""
        self.convertAudioCodec = AudioCodec(rawValue: audioCodecString) ?? self.convertAudioCodec
        self.convertVideoSubtitleScan = (try? json.get("convertVideoSubtitleScan")) ?? self.convertVideoSubtitleScan
        let languageString = (try? json.get("convertLanguage")) ?? ""
        self.convertLanguage = Language(rawValue: languageString) ?? self.convertLanguage
        self.convertVideoMaxFramerate = (try? json.get("convertVideoMaxFramerate")) ?? self.convertVideoMaxFramerate
        self.deleteSubtitles = (try? json.get("deleteSubtitles")) ?? self.deleteSubtitles

        self.logLevel = (try? json.get("logLevel")) ?? self.logLevel
        if let lFile: String = try? json.get("logFile") {
            logFile = Path(lFile)
        } else {
            logFile = nil
        }

        if !self.plexDirectory.exists {
            try self.plexDirectory.mkpath()
        }
        guard self.plexDirectory.exists else {
            throw ConfigError.pathDoesNotExist(self.plexDirectory)
        }
        guard self.plexDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory(self.plexDirectory)
        }

        for d in self.downloadDirectories + self.homeVideoDownloadDirectories {
            if !d.exists {
                try d.mkpath()
            }
            guard d.exists else {
                throw ConfigError.pathDoesNotExist(d)
            }
            guard d.isDirectory else {
                throw ConfigError.pathIsNotDirectory(d)
            }
        }

        if self.convert {
            if !self.convertTempDirectory.exists {
                try self.convertTempDirectory.mkpath()
            }
            guard self.convertTempDirectory.exists else {
                throw ConfigError.pathDoesNotExist(self.convertTempDirectory)
            }
            guard self.convertTempDirectory.isDirectory else {
                throw ConfigError.pathIsNotDirectory(self.convertTempDirectory)
            }
        }
    }

    /**
     Creates a JSON object from self

     - Returns: A JSON representation of the Config
    */
    func encoded() -> JSON {
        var json: JSON = [
            "plexDirectory": plexDirectory.string,
            "downloadDirectories": downloadDirectories.map({ $0.string }).encoded(),
            "homeVideoDownloadDirectories": homeVideoDownloadDirectories.map({ $0.string }).encoded(),
            "convert": convert,
            "convertImmediately": convertImmediately,
            "convertCronStart": convertCronStart,
            "convertCronEnd": convertCronEnd,
            "convertThreads": convertThreads,
            "deleteOriginal": deleteOriginal,
            "convertVideoContainer": convertVideoContainer.rawValue,
            "convertVideoCodec": convertVideoCodec.rawValue,
            "convertAudioContainer": convertAudioContainer.rawValue,
            "convertAudioCodec": convertAudioCodec.rawValue,
            "convertVideoSubtitleScan": convertVideoSubtitleScan,
            "convertLanguage": convertLanguage.rawValue,
            "convertVideoMaxFramerate": convertVideoMaxFramerate,
            "convertTempDirectory": convertTempDirectory.string,
            "deleteSubtitles": deleteSubtitles,
            "logLevel": logLevel
        ]
        if let lFile = logFile {
            json["logFile"] = lFile.string.encoded()
        }
        return json
    }

    /**
     Creates a JSON string of self

     - Returns: A string of the serialized JSON config
    */
    func serialized() throws -> String {
        return try self.encoded().serialized()
    }

    /** Creates a printable representation of self
     - Returns: A string of serialized JSON config
    */
    func printable() -> String {
        var download: [String] = []
        for d in downloadDirectories {
            download.append(d.string)
        }
        var home: [String] = []
        for h in homeVideoDownloadDirectories {
            home.append(h.string)
        }
        var dict: [String: JSONRepresentable] = [
            "plexDirectory": plexDirectory.string,
            "downloadDirectories": download.joined(separator: ", "),
            "homeVideoDownloadDirectories": home.joined(separator: ", "),
            "convert": convert,
            "convertImmediately": convertImmediately,
            "convertCronStart": convertCronStart.string,
            "convertCronEnd": convertCronEnd.string,
            "convertThreads": convertThreads,
            "deleteOriginal": deleteOriginal,
            "convertVideoContainer": convertVideoContainer.rawValue,
            "convertVideoCodec": convertVideoCodec.rawValue,
            "convertAudioContainer": convertAudioContainer.rawValue,
            "convertAudioCodec": convertAudioCodec.rawValue,
            "convertVideoSubtitleScan": convertVideoSubtitleScan,
            "convertLanguage": convertLanguage.rawValue,
            "convertVideoMaxFramerate": convertVideoMaxFramerate,
            "convertTempDirectory": convertTempDirectory.string,
            "deleteSubtitles": deleteSubtitles,
            "logLevel": logLevel
        ]
        if let lFile = logFile {
            dict["logFile"] = lFile.string
        }
        var str: String = ""
        for (key, value) in dict {
            str += "\t\(key): \(value)\n"
        }
        return str
    }

    /// Writes the config to the configFile path
    func save() throws {
        try configFile.write(self.serialized(), force: true)
    }
}

protocol ConversionConfig {}

struct VideoConversionConfig: ConversionConfig {
    var container: VideoContainer
    var videoCodec: VideoCodec
    var audioCodec: AudioCodec
    var subtitleScan: Bool
    var mainLanguage: Language
    var maxFramerate: Double
    var plexDir: Path
    var tempDir: Path?
}

struct AudioConversionConfig: ConversionConfig {
    var container: AudioContainer
    var codec: AudioCodec
    var plexDir: Path
    var tempDir: Path?
}
