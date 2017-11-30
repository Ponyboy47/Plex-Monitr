/*

    Config.swift

    Created By: Jacob Williams
    Description: This file contains the Config structure for the Monitr class
    License: MIT License

*/

import Foundation
import PathKit
import SwiftyBeaver
import Cron

enum ConfigError: Error {
    case incorrectPathType(Path, Bool)
    case pathDoesNotExist(Path)
    case invalidCronString(String)
}

struct Config: Codable {
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
            newValue.forEach { dir in
                downloadWatchers.append(DirectoryMonitor(URL: dir.absolute.url))
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
            newValue.forEach { dir in
                homeVideoDownloadWatchers.append(DirectoryMonitor(URL: dir.absolute.url))
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
    var deleteOriginal: Bool = false
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
    var convertTempDirectory: Path = "/tmp/monitrConversions"
    /// Whether external subtitle files should be deleted upon import with Monitr
    var deleteSubtitles: Bool = false

    var logFile: Path?
    var logLevel: Int = 0
    var logger: SwiftyBeaver.Type

    /// Watches the download directory for new files
    private var downloadWatchers: [DirectoryMonitor?] = []
    /// Watches the home video download directory for new files
    private var homeVideoDownloadWatchers: [DirectoryMonitor?] = []

    enum CodingKeys: String, CodingKey {
        case plexDirectory
        case downloadDirectories
        case downloadDirectory
        case homeVideoDownloadDirectories
        case convertTempDirectory
        case convert
        case convertImmediately
        case convertCronStart
        case convertCronEnd
        case convertThreads
        case deleteOriginal
        case convertVideoContainer
        case convertVideoCodec
        case convertAudioContainer
        case convertAudioCodec
        case convertVideoSubtitleScan
        case convertLanguage
        case convertVideoMaxFramerate
        case deleteSubtitles
        case logLevel
        case logFile
    }

    init(_ logger: SwiftyBeaver.Type) {
        self.logger = logger
    }

    /// Initializes by reading the file at the path as a JSON string
    init(fromFile configFile: Path, with logger: SwiftyBeaver.Type) throws {
        self = try configFile.decode(with: JSONDecoder(), to: Config.self)
        self.configFile = configFile
        self.logger = logger
    }

    /// Initialize the config from a JSON object
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        logger = SwiftyBeaver.self

        plexDirectory = try values.decode(Path.self, forKey: .plexDirectory)

        self.convertTempDirectory = try values.decode(Path.self, forKey: .convertTempDirectory)
        self.convert = try values.decode(Bool.self, forKey: .convert)
        self.convertImmediately = try values.decode(Bool.self, forKey: .convertImmediately)
        self.convertCronStart = try values.decode(DatePattern.self, forKey: .convertCronStart)
        self.convertCronEnd = try values.decode(DatePattern.self, forKey: .convertCronEnd)
        self.convertThreads = try values.decode(Int.self, forKey: .convertThreads)
        self.deleteOriginal = try values.decode(Bool.self, forKey: .deleteOriginal)
        self.convertVideoContainer = try values.decode(VideoContainer.self, forKey: .convertVideoContainer)
        self.convertVideoCodec = try values.decode(VideoCodec.self, forKey: .convertVideoCodec)
        self.convertAudioContainer = try values.decode(AudioContainer.self, forKey: .convertAudioContainer)
        self.convertAudioCodec = try values.decode(AudioCodec.self, forKey: .convertAudioCodec)
        self.convertVideoSubtitleScan = try values.decode(Bool.self, forKey: .convertVideoSubtitleScan)
        self.convertLanguage = try values.decode(Language.self, forKey: .convertLanguage)
        self.convertVideoMaxFramerate = try values.decode(Double.self, forKey: .convertVideoMaxFramerate)
        self.deleteSubtitles = try values.decode(Bool.self, forKey: .deleteSubtitles)

        self.logLevel = try values.decode(Int.self, forKey: .logLevel)
        self.logFile = try values.decode(Path?.self, forKey: .logFile)

        downloadDirectories = try values.decode([Path].self, forKey: .downloadDirectories)
        if let downloadDir: Path = try values.decodeIfPresent(Path.self, forKey: .downloadDirectory) {
            downloadDirectories.append(downloadDir)
        }

        self.homeVideoDownloadDirectories = try values.decode([Path].self, forKey: .homeVideoDownloadDirectories)

        try createAndValidate(path: self.plexDirectory, isDirectory: true)

        for d in self.downloadDirectories + self.homeVideoDownloadDirectories {
            try createAndValidate(path: d, isDirectory: true)
        }

        if self.convert {
            try createAndValidate(path: self.convertTempDirectory, isDirectory: true)
        }
    }

    private func create(path: Path) throws {
        guard !path.exists else { return }

        try path.mkpath()

        guard path.exists else {
            throw ConfigError.pathDoesNotExist(path)
        }
    }

    private func validate(path: Path, isDirectory: Bool = false) throws {
        guard path.isDirectory == isDirectory else {
            throw ConfigError.incorrectPathType(path, isDirectory)
        }
    }

    private func createAndValidate(path: Path, isDirectory: Bool = false) throws {
        try create(path: path)
        try validate(path: path, isDirectory: isDirectory)
    }

    /// Starts monitoring the downloads directory for changes
    @discardableResult
    func startMonitoring() -> Bool {
        for watcher in self.downloadWatchers + self.homeVideoDownloadWatchers {
            do {
                try watcher?.startMonitoring()
            } catch {
                logger.warning("Failed to start the directory watcher for '\(String(describing: watcher?.URL.path))'.")
                logger.error(error)
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

    /**
     Creates a JSON object from self

     - Returns: A JSON representation of the Config
    */
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plexDirectory, forKey: .plexDirectory)
        try container.encode(downloadDirectories, forKey: .downloadDirectories)
        try container.encode(homeVideoDownloadDirectories, forKey: .homeVideoDownloadDirectories)
        try container.encode(convert, forKey: .convert)
        try container.encode(convertImmediately, forKey: .convertImmediately)
        try container.encode(convertCronStart, forKey: .convertCronStart)
        try container.encode(convertCronEnd, forKey: .convertCronEnd)
        try container.encode(convertThreads, forKey: .convertThreads)
        try container.encode(deleteOriginal, forKey: .deleteOriginal)
        try container.encode(convertVideoContainer, forKey: .convertVideoContainer)
        try container.encode(convertVideoCodec, forKey: .convertVideoCodec)
        try container.encode(convertAudioContainer, forKey: .convertAudioContainer)
        try container.encode(convertAudioCodec, forKey: .convertAudioCodec)
        try container.encode(convertVideoSubtitleScan, forKey: .convertVideoSubtitleScan)
        try container.encode(convertLanguage, forKey: .convertLanguage)
        try container.encode(convertVideoMaxFramerate, forKey: .convertVideoMaxFramerate)
        try container.encode(convertTempDirectory, forKey: .convertTempDirectory)
        try container.encode(deleteSubtitles, forKey: .deleteSubtitles)
        try container.encode(logLevel, forKey: .logLevel)
        try container.encode(logFile, forKey: .logFile)
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
        var dict: [String: Any] = [
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
        let data = try JSONEncoder().encode(self)
        let str = String(data: data, encoding: .utf8)!
        try configFile.write(str, force: true)
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

    init(config: Config) {
        container = config.convertVideoContainer
        videoCodec = config.convertVideoCodec
        audioCodec = config.convertAudioCodec
        subtitleScan = config.convertVideoSubtitleScan
        mainLanguage =  config.convertLanguage
        maxFramerate = config.convertVideoMaxFramerate
        plexDir = config.plexDirectory
        tempDir = config.deleteOriginal ? config.convertTempDirectory : nil
    }
}

struct AudioConversionConfig: ConversionConfig {
    var container: AudioContainer
    var codec: AudioCodec
    var plexDir: Path
    var tempDir: Path?

    init(config: Config) {
        container = config.convertAudioContainer
        codec = config.convertAudioCodec
        plexDir = config.plexDirectory
        tempDir = config.deleteOriginal ? config.convertTempDirectory : nil
    }
}
