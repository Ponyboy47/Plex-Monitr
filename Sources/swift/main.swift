/*

    main.swift

    Created By: Jacob Williams
    Description: This is the main source file that will set up the config and
                   start the monitoring
    License: MIT License

*/

import Foundation
import PathKit
import Signals
import Async
#if os(Linux)
import Dispatch
#endif

var monitr: Monitr
let argParser = ArgumentParser("\(CommandLine.arguments.first!) [Options]")

// Args/Flags to configure this program from the CLI
let configOption = try Option<Path>("f", longName: "config", default: Path("~/.config/monitr/settings.json"), description: "The file from which to read configuration options", parser: argParser)
let plexDirOption = try Option<Path>("p", longName: "plex-dir", description: "The directory where the Plex libraries reside", parser: argParser)
let downloadDirOption = try Option<Path>("t", longName: "download-dir", description: "The directory where media downloads reside", parser: argParser)
let convertFlag = try Flag("c", longName: "convert", description: "Whether or not newly added files should be converted to a Plex DirectPlay format", parser: argParser)
let saveFlag = try Flag("s", longName: "save-settings", default: true, description: "Whether or not the configured settings should be saved to the config options file", parser: argParser)

// Prints the help/usage text if -h or --help was used
var h: Bool = false
do {
    if let help = try ArgumentParser.parse(longName: "help", isBool: true) {
        h = try Bool.from(string: help)
    } else if let help = try ArgumentParser.parse(shortName: "h", isBool: true) {
        h = try Bool.from(string: help)
    }
} catch {
    print("An error occured determing if the help/usage text needed to be displayed.\n\t\(error)")
}
if h {
    print("Usage: \(argParser.usage)\n\nOptions:")
    var longest = 0
    argParser.arguments.forEach { arg in
        if let flag = arg as? Flag {
            let _ = flag.usage
            longest = flag.usageDescriptionActualLength > longest ? flag.usageDescriptionActualLength : longest
        } else if let path = arg as? Option<Path> {
            let _ = path.usage
            longest = path.usageDescriptionActualLength > longest ? path.usageDescriptionActualLength : longest
        }
    }
    for argument in argParser.arguments {
        if let flag = argument as? Flag {
            flag.usageDescriptionNiceLength = longest + 4
            print(flag.usage)
        } else if let path = argument as? Option<Path> {
            path.usageDescriptionNiceLength = longest + 4
            print(path.usage)
        } else {
            continue
        }
    }
    exit(EXIT_SUCCESS)
}

guard let configPath: Path = try configOption.parse() else {
    print("Something went wrong and the configPath option was not set")
    exit(EXIT_FAILURE)
}
guard let saveConfig: Bool = try saveFlag.parse() else {
    print("Something went wrong and the save flag was not set")
    exit(EXIT_FAILURE)
}

let plexDirectory: Path? = try plexDirOption.parse()
let downloadDirectory: Path? = try downloadDirOption.parse()
let convert: Bool? = try convertFlag.parse()
// We'll use this in a minute to make sure the config is a json file (hopefully people use file extensions if creating their config manually)
let ext = (configPath.extension ?? "").lowercased()

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
Signals.trap(signals: [.int, .term, .kill, .quit]) { _ in
    print("Received signal. Stopping monitr.")
    monitr.shutdown()
    exit(EXIT_SUCCESS)
}

// Run once and then start monitoring regularly
monitr.run()
monitr.setDelegate()
monitr.startMonitoring()

let group = DispatchGroup()
group.enter()
group.wait()
