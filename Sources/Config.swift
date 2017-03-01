/*

    Config.swift

    Created By: Jacob Williams
    Description: This file contains the Config structure for the Monitr class
    License: MIT License

*/

import Foundation
import PathKit
import JSON

enum ConfigError: Swift.Error {
    case pathIsNotDirectory
    case pathDoesNotExist
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
            #if os(Linux)
            downloadWatcher = DirectoryMonitor()
            #else
            downloadWatcher = DirectoryMonitor(URL: newValue.url)
            #endif
        }
        get {
            return _downloadDirectory
        }
    }
    /// Whether the media should be converted to Plex DirectPlay formats automatically
    var convert: Bool = false

    /// Watches the download directory for new files
    private var downloadWatcher: DirectoryMonitor?

    init(_ configFile: Path? = nil, _ plexDirectory: Path? = nil, _ downloadDirectory: Path? = nil, _ convert: Bool? = nil) throws {
        self.configFile = configFile ?? self.configFile
        self.plexDirectory = plexDirectory ?? self.plexDirectory
        self.downloadDirectory = downloadDirectory ?? self._downloadDirectory
        self.convert = convert ?? self.convert

        // Verify the plex/download directories exist and are in fact, directories

        guard self.plexDirectory.exists else {
            throw ConfigError.pathDoesNotExist
        }
        guard self.plexDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory
        }

        guard self.downloadDirectory.exists else {
            throw ConfigError.pathDoesNotExist
        }
        guard self.downloadDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory
        }
    }

    /// Starts monitoring the downloads directory for changes
    func startMonitoring() {
        downloadWatcher?.startMonitoring()
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
    init(_ path: Path) throws {
        try self.init(path.read())
        configFile = path
    }

    /// Initialize by reading the string as JSON
    init(_ str: String) throws {
        try self.init(json: JSON(str))
    }

    /// Initialize the config from a JSON object
    init(json: JSON) throws {
        plexDirectory = Path(try json.get("plexDirectory"))
        downloadDirectory = Path(try json.get("downloadDirectory"))
        convert = try json.get("convert")

        guard plexDirectory.exists else {
            throw ConfigError.pathDoesNotExist
        }
        guard plexDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory
        }

        guard downloadDirectory.exists else {
            throw ConfigError.pathDoesNotExist
        }
        guard downloadDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory
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
        return [
            "plexDirectory": plexDirectory.string,
            "downloadDirectory": downloadDirectory.string,
            "convert": convert
        ]
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
        try configFile.write(self.serialized())
    }
}
