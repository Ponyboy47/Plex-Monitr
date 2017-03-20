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

enum ConfigError: Error {
    case pathIsNotDirectory(Path)
    case pathDoesNotExist(Path)
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
    var logFile: Path?
    var log: SwiftyBeaver.Type

    /// Watches the download directory for new files
    private var downloadWatcher: DirectoryMonitor?

    init(_ configFile: Path? = nil, _ plexDirectory: Path? = nil, _ downloadDirectory: Path? = nil, _ convert: Bool? = nil, _ logFile: Path? = nil, logger: SwiftyBeaver.Type) throws {
        self.log = logger
        self.configFile = configFile ?? self.configFile
        self.plexDirectory = plexDirectory ?? self.plexDirectory
        self.downloadDirectory = downloadDirectory ?? self._downloadDirectory
        self.convert = convert ?? self.convert
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
        try self.init(path.read(), logger: logger)
        configFile = path
    }

    /// Initialize by reading the string as JSON
    init(_ str: String, logger: SwiftyBeaver.Type) throws {
        try self.init(json: JSON.Parser.parse(str), logger: logger)
    }

    /// Initialize the config from a JSON object
    init(json: JSON, logger: SwiftyBeaver.Type) throws {
        try self.init(json: json)
        log = logger
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
            "convert": convert
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
