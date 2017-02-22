import Foundation
import PathKit
import JSON

struct Config {
    var configFile: Path = "~/.config/monitr/settings.json"
    var plexDirectory: Path = "/var/lib/plexmediaserver/Library"
    private var _torrentDirectory: Path = "/var/lib/deluge/Downloads"
    var torrentDirectory: Path {
        set {
            _torrentDirectory = newValue
            torrentWatcher = DirectoryMonitor(URL: newValue.url)
        }
        get {
            return _torrentDirectory
        }
    }
    var convert: Bool = false

    var torrentWatcher: DirectoryMonitor?

    init(_ configFile: Path? = nil, _ plexDirectory: Path? = nil, _ torrentDirectory: Path? = nil, _ convert: Bool? = nil) throws {
        self.configFile = configFile ?? self.configFile
        self.plexDirectory = plexDirectory ?? self.plexDirectory
        self.torrentDirectory = torrentDirectory ?? self._torrentDirectory
        self.convert = convert ?? self.convert

        guard self.plexDirectory.exists else {
            throw ConfigError.pathDoesNotExist
        }
        guard self.plexDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory
        }

        guard self.torrentDirectory.exists else {
            throw ConfigError.pathDoesNotExist
        }
        guard self.torrentDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory
        }
    }
}

extension Config: JSONInitializable {
    init(_ path: Path) throws {
        try self.init(path.read())
    }

    init(_ str: String) throws {
        try self.init(json: JSON(str))
    }

    init(json: JSON) throws {
        plexDirectory = Path(try json.get("plexDirectory"))
        torrentDirectory = Path(try json.get("torrentDirectory"))
        convert = try json.get("convert")

        guard plexDirectory.exists else {
            throw ConfigError.pathDoesNotExist
        }
        guard plexDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory
        }

        guard torrentDirectory.exists else {
            throw ConfigError.pathDoesNotExist
        }
        guard torrentDirectory.isDirectory else {
            throw ConfigError.pathIsNotDirectory
        }
    }
}

extension Config: JSONRepresentable {
    func encoded() -> JSON {
        return [
            "plexDirectory": plexDirectory.string,
            "torrentDirectory": torrentDirectory.string,
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
