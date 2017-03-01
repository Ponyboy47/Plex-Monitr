/*

    main.swift

    Created By: Jacob Williams
    Description: This is the main source file that will set up the config and
                   start the monitoring
    License: MIT License

*/

import Foundation
import Guaka
import PathKit
import Signals

// Need the global so that we can access it in and out of closures
var monitr: Monitr?

// Args/Flags to configure this program from the CLI
let configFlag = Flag(shortName: "f", longName: "config", value: Path("~/.config/monitr/settings.json"), description: "The file from which to read configuration options")
let plexDirFlag = Flag(shortName: "p", longName: "plex-dir", type: Path.self, description: "The directory where the Plex libraries reside")
let downloadDirFlag = Flag(shortName: "t", longName: "download-dir", type: Path.self, description: "The directory where media downloads reside")
let convertFlag = Flag(shortName: "c", longName: "convert", type: Bool.self, description: "Whether or not newly added files should be converted to a Plex DirectPlay format")
let saveFlag = Flag(shortName: "s", longName: "save-settings", value: true, description: "Whether or not the configured settings should be saved to the config options file")

// The main command to execute
let main = Command(usage: "", flags: [configFlag, plexDirFlag, downloadDirFlag, convertFlag, saveFlag]) { flags, _ in
    // Check for the configPath argument (since there's a default value it should never be nil)
    guard let configPath = flags.getPath(name: "config") else {
        print("Something went very wrong and the config option is not set")
        return
    }

    // Check for the saveConfig argument (since there's a default value it should never be nil)
    guard let saveConfig = flags.getBool(name: "save-settings") else {
        print("Something went very wrong and the save-settings option is not set")
        return
    }

    // We'll use this in a minute to make sure the config is a json file (hopefully people use file extensions if creating their config manually)
    let ext = (configPath.extension ?? "").lowercased()

    // Get all the optional arguments now
    let plexDirectory = flags.getPath(name: "plex-dir")
    let downloadDirectory = flags.getPath(name: "download-dir")
    let convert = flags.getBool(name: "convert")

    // Try and create the Config
    var config: Config
    // Make sure it's a real file and it ahs the json extension
    if configPath.isFile && ext == "json" {
        // Try and read the config from it's file
        do {
            config = try Config(configPath)
        } catch {
            print("Failed to initialize config from JSON file.\n\t\(error)")
            exit(EXIT_FAILURE)
        }
        // If an optional arg was specified, change it in the config
        if let p = plexDirectory {
            config.plexDirectory = p
        }
        if let t = downloadDirectory {
            config.downloadDirectory = t
        }
        if let c = convert {
            config.convert = c
        }
    } else {
        // Try and create the Config from the command line args (fails if anything is not set)
        do {
            config = try Config(configPath, plexDirectory, downloadDirectory, convert)
        } catch {
            print("Failed to initialize config.\n\t\(error)")
            exit(EXIT_FAILURE)
        }
    }

    // Try and save the config (if the flag is set to true)
    if saveConfig {
        do {
            try config.save()
        } catch {
            print("Failed to save configuration to file:\n\t\(error)")
        }
    }

    // Create the monitr
    monitr = Monitr(config)

    // Watch for signals so we can shut down properly
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

    // Run once and then start monitoring regularly
    monitr?.run()
    monitr?.setDelegate()
    monitr?.startMonitoring()
}

main.execute()
