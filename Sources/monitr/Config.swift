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
    private var _downloadDirectory: Path = "/var/lib/deluge/Downloads"
    var downloadDirectory: Path {
        set {
            // When this is set, update the DirectoryMonitor
            _downloadDirectory = newValue
            downloadWatcher = DirectoryMonitor(URL: newValue.url)
        }
        get {
            return _downloadDirectory
        }
    }
    /// Whether the media should be converted to Plex DirectPlay formats automatically
    var convert: Bool = false
    /// Whether media should be converted immediately, or during a configurable time when the server is less likely to be busy
    var convertImmediately: Bool = true
    /// The Cron string describing when scheduled media conversions may begin
    var convertCronStart: String = "0 0 0 * * * *"
    /// The Cron string describing when scheduled media conversions should be finished
    var convertCronEnd: String = "0 0 8 * * * *"
    /// The number of simultaneous threads to convert media on
    var convertThreads: Int = 2
    /// Whether the original media file should be deleted after a successful conversion
    var deleteOriginal: Bool = true

    /// The queue of conversion jobs
    var conversionQueue: ConversionQueue?

    var logFile: Path?
    var logLevel: Int = 0
    var log: SwiftyBeaver.Type

    /// Watches the download directory for new files
    private var downloadWatcher: DirectoryMonitor?

    init(_ configFile: Path? = nil, _ plexDirectory: Path? = nil, _ downloadDirectory: Path? = nil, _ convert: Bool? = nil, _ convertImmediately: Bool? = nil, _ convertCronStart: String? = nil, _ convertCronEnd: String? = nil, _ convertThreads: Int? = nil, _ deleteOriginal: Bool? = nil, _ logLevel: Int? = nil, _ logFile: Path? = nil, logger: SwiftyBeaver.Type) throws {
        self.log = logger
        self.configFile = configFile ?? self.configFile
        self.plexDirectory = plexDirectory ?? self.plexDirectory
        self.downloadDirectory = downloadDirectory ?? self._downloadDirectory
        self.convert = convert ?? self.convert
        self.convertImmediately = convertImmediately ?? self.convertImmediately
        self.convertCronStart = convertCronStart ?? self.convertCronStart
        self.convertCronEnd = convertCronEnd ?? self.convertCronEnd
        self.convertThreads = convertThreads ?? self.convertThreads
        self.deleteOriginal = deleteOriginal ?? self.deleteOriginal
        self.logLevel = logLevel ?? self.logLevel
        self.logFile = logFile

        // Verify the plex/download directories exist and are in fact, directories

        guard self.plexDirectory.exists else {
            throw ConfigError.pathDoesNotExist(self.plexDirectory)
        }
        guard self.plexDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory(self.plexDirectory)
        }

        guard self.downloadDirectory.exists else {
            throw ConfigError.pathDoesNotExist(self.downloadDirectory)
        }
        guard self.downloadDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory(self.downloadDirectory)
        }

        // Validate the Cron strings
        guard let _ = try? Cron.parseExpression(self.convertCronStart) else {
            throw ConfigError.invalidCronString(self.convertCronStart)
        }
        guard let _ = try? Cron.parseExpression(self.convertCronEnd) else {
            throw ConfigError.invalidCronString(self.convertCronEnd)
        }
    }

    /// Starts monitoring the downloads directory for changes
    @discardableResult
    func startMonitoring() -> Bool {
        do {
            try downloadWatcher?.startMonitoring()
        } catch {
            log.warning("Failed to start directory watcher.")
            log.error(error)
            return false
        }
        return true
    }

    /// Stops monitoring the downloads directory
    func stopMonitoring() {
       downloadWatcher?.stopMonitoring()
    }

    /// Sets the delegate of the downloadWatcher
    func setDelegate(_ delegate: DirectoryMonitorDelegate) {
        downloadWatcher?.delegate = delegate
    }
}

/// Allows the config to be initialized from a json file
extension Config: JSONInitializable {
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

        plexDirectory = Path(try json.get("plexDirectory"))
        downloadDirectory = Path(try json.get("downloadDirectory"))
        do {
            convert = try json.get("convert")
        } catch {
            convert = false
        }
        do {
            convertImmediately = try json.get("convertImmediately")
        } catch {
            convertImmediately = true
        }
        do {
            convertCronStart = try json.get("convertCronStart")
            try Cron.parseExpression(convertCronStart)
        } catch {
            convertCronStart = "0 0 0 * * * *"
        }
        do {
            convertCronEnd = try json.get("convertCronEnd")
            try Cron.parseExpression(convertCronStart)
        } catch {
            convertCronEnd = "0 0 8 * * * *"
        }
        do {
            convertThreads = try json.get("convertThreads")
        } catch {
            convertThreads = 2
        }
        do {
            deleteOriginal = try json.get("deleteOriginal")
        } catch {
            deleteOriginal = true
        }
        do {
            logLevel = try json.get("logLevel")
        } catch {
            logLevel = 0
        }
        if let lFile: String = try? json.get("logFile") {
            logFile = Path(lFile)
        } else {
            logFile = nil
        }

        guard plexDirectory.exists else {
            throw ConfigError.pathDoesNotExist(plexDirectory)
        }
        guard plexDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory(plexDirectory)
        }

        guard downloadDirectory.exists else {
            throw ConfigError.pathDoesNotExist(downloadDirectory)
        }
        guard downloadDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory(downloadDirectory)
        }
    }
}

/// Allows the config to output/represented as JSON
extension Config: JSONRepresentable {
    /**
     Creates a JSON object from self

     - Returns: A JSON representation of the Config
    */
    func encoded() -> JSON {
        var json: JSON = [
            "plexDirectory": plexDirectory.string,
            "downloadDirectory": downloadDirectory.string,
            "convert": convert,
            "convertImmediately": convertImmediately,
            "convertCronStart": convertCronStart,
            "convertCronEnd": convertCronEnd,
            "convertThreads": convertThreads,
            "deleteOriginal": deleteOriginal,
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

    /// Writes the config to the configFile path
    func save() throws {
        try configFile.write(self.serialized(), force: true)
    }
}
