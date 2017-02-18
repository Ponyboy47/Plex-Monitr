import Foundation
import PathKit
import JSON

struct Config {
    var configFile: Path = "~/.config/monitr/settings.json"
    var plexDir: String = "/var/lib/plexmediaserver/Library"
    var torrentDir: String = "/var/lib/deluge"
    var watchTime: Double = 60.0
    var convert = false

    init(_ configFile: Path? = nil, _ plexDir: String? = nil, _ torrentDir: String? = nil, _ watchTime: Double? = nil, _ convert: Bool? = nil) {
        self.configFile = configFile ?? self.configFile
        self.plexDir = plexDir ?? self.plexDir
        self.torrentDir = torrentDir ?? self.torrentDir
        self.watchTime = watchTime ?? self.watchTime
        self.convert = convert ?? self.convert
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
        plexDir = try json.get("plexDir")
        torrentDir = try json.get("torrentDir")
        watchTime = try json.get("watchTime")
        convert = try json.get("convert")
    }
}

extension Config: JSONRepresentable {
    func encoded() -> JSON {
        return [
            "plexDir": plexDir,
            "torrentDir": torrentDir,
            "watchTime": watchTime,
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
