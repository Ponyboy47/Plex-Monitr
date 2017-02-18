import Commander
import PathKit
import Regex
import JSON

// Create the base command/options to execute
let main = command(
    Option<String>("config", default: "~/.config/monitr/settings.json", flag: "f", description: "The file from which to read configuration options"),
    Option<String>("plex-dir", flag: Character("p"), description: "The directory where the Plex libraries reside"),
    Option<String>("torrent-dir", flag: Character("t"), description: "The directory where the torrent directories reside"),
    Option<Double>("watch-time", flag: Character("w"), description: "How often to check the torrent downloads directory for new downloads"),
    Flag("convert", flag: Character("c"), description: "Whether or not newly added files should be converted to a Plex DirectPlay format", default: nil),
    Flag("save-settings", flag: Character("s"), description: "Whether or not the configured settings should be saved to the config options file", default: true)
    ) { configFile, plexDir, torrentDir, watchTime, convert, saveConfig in
    var config: Config

    // Check if the config file's path is a JSON file
    let configFile = Path(configFile)
    if configFile.isFile && Regex("json", options: [.IgnoreCase]).matches(configFile.extension ?? "") {
        // Try and create a config from the JSON
        config = try Config(configFile)
        config.configFile = configFile
        if let p = plexDir {
            config.plexDir = p
        }
        if let t = torrentDir {
            config.torrentDir = t
        }
        if let w = watchTime {
            config.watchTime = w
        }
        if let c = convert {
            config.convert = c
        }
    } else {
        config = Config(configFile, plexDir, torrentDir, watchTime, convert)
    }

    if saveConfig! {
        do {
            try config.save()
        } catch {
            print("Failed to save configuration to file:\n\t\(error)")
        }
    }

    // Do the real stuff here
}

main.run()
