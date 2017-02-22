import Foundation
import Guaka
import PathKit
import Signals

var monitr: Monitr?

let configFlag = Flag(shortName: "f", longName: "config", value: Path("~/.config/monitr/settings.json"), description: "The file from which to read configuration options")
let plexDirFlag = Flag(shortName: "p", longName: "plex-dir", type: Path.self, description: "The directory where the Plex libraries reside")
let torrentDirFlag = Flag(shortName: "t", longName: "torrent-dir", type: Path.self, description: "The directory where the torrent downloads reside")
let convertFlag = Flag(shortName: "c", longName: "convert", type: Bool.self, description: "Whether or not newly added files should be converted to a Plex DirectPlay format")
let saveFlag = Flag(shortName: "s", longName: "save-settings", value: true, description: "Whether or not the configured settings should be saved to the config options file")

let main = Command(usage: "", flags: [configFlag, plexDirFlag, torrentDirFlag, convertFlag, saveFlag]) { flags, _ in
    let configPath = flags.getPath(name: "config")!
    let ext = configPath.extension ?? ""

    let plexDirectory = flags.getPath(name: "plex-dir")
    let torrentDirectory = flags.getPath(name: "torrent-dir")
    let convert = flags.getBool(name: "convert")
    let saveConfig = flags.getBool(name: "save-settings")!

    var config: Config
    if configPath.isFile && ext.lowercased() == "json" {
        do {
            config = try Config(configPath)
        } catch {
            print("Failed to initialize config from JSON file.\n\t\(error)")
            exit(EXIT_FAILURE)
        }
        if let p = plexDirectory {
            config.plexDirectory = p
        }
        if let t = torrentDirectory {
            config.torrentDirectory = t
        }
        if let c = convert {
            config.convert = c
        }
    } else {
        do {
            config = try Config(configPath, plexDirectory, torrentDirectory, convert)
        } catch {
            print("Failed to initialize config.\n\t\(error)")
            exit(EXIT_FAILURE)
        }
    }

    if saveConfig {
        do {
            try config.save()
        } catch {
            print("Failed to save configuration to file:\n\t\(error)")
        }
    }
    monitr = Monitr(config)

    Signals.trap(signal: .int) { signal in
        print("Received interrupt signal. Stopping monitr.")
        monitr?.shutdown()
    }
    Signals.trap(signal: .term) { signal in
        print("Received terminate signal. Stopping monitr.")
        monitr?.shutdown()
    }
    Signals.trap(signal: .kill) { signal in
        print("Received kill signal. Immediately stopping monitr.")
        monitr?.shutdown()
    }

    monitr?.run()
    monitr?.startMonitoring()
}

main.execute()
