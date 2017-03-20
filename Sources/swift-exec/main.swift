/*

    main.swift

    Created By: Jacob Williams
    Description: This is the main source file that will set up the config and
                   start the monitoring
    License: MIT License

*/

import Foundation
import SwiftyBeaver
import PathKit
import Signals
import Async
#if os(Linux)
import Dispatch
#endif

let log = SwiftyBeaver.self

var monitr: Monitr
let argParser = ArgumentParser("\(CommandLine.arguments.first!) [Options]")

// Args/Flags to configure this program from the CLI
let configOption = try Option<Path>("f", longName: "config", default: Path("~/.config/monitr/settings.json"), description: "The file from which to read configuration options", parser: argParser)
let plexDirOption = try Option<Path>("p", longName: "plex-dir", description: "The directory where the Plex libraries reside", parser: argParser)
let downloadDirOption = try Option<Path>("t", longName: "download-dir", description: "The directory where media downloads reside", parser: argParser)
let convertFlag = try Flag("c", longName: "convert", description: "Whether or not newly added files should be converted to a Plex DirectPlay format", parser: argParser)
let saveFlag = try Flag("s", longName: "save-settings", default: false, description: "Whether or not the configured settings should be saved to the config options file", parser: argParser)
let logLevelOption = try Option<Int>("d", default: 0, description: "The logging level to use. Higher numbers mean more logging. Valid number range is 0-4.", parser: argParser)
let logFileOption = try Option<Path>("l", longName: "log-file", description: "Where to write the log file.", parser: argParser)

// Prints the help/usage text if -h or --help was used
var h: Bool = false
do {
    if let help = ArgumentParser.parse(longName: "help", isBool: true) {
        h = try Bool.from(string: help)
    } else if let help = ArgumentParser.parse(shortName: "h", isBool: true) {
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
        } else if let int = arg as? Option<Int> {
            let _ = int.usage
            longest = int.usageDescriptionActualLength > longest ? int.usageDescriptionActualLength : longest
        }
    }
    for argument in argParser.arguments {
        if let flag = argument as? Flag {
            flag.usageDescriptionNiceLength = longest + 4
            print(flag.usage)
        } else if let path = argument as? Option<Path> {
            path.usageDescriptionNiceLength = longest + 4
            print(path.usage)
        } else if let int = argument as? Option<Int> {
            int.usageDescriptionNiceLength = longest + 4
            print(int.usage)
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
guard var logLevel: Int = try logLevelOption.parse() else {
    print("Something went wrong and the logLevel option was not set")
    exit(EXIT_FAILURE)
}
// Caps logLevel to the maximum/minimum level
if logLevel > 4 {
    logLevel = 4
} else if logLevel < 0 {
    logLevel = 0
}
let minLevel = SwiftyBeaver.Level(rawValue: 4 - logLevel)!

let console = ConsoleDestination()
console.minLevel = minLevel
log.addDestination(console)

log.verbose("Got minimum required arguments from the CLI.")

let plexDirectory: Path? = try plexDirOption.parse()
let downloadDirectory: Path? = try downloadDirOption.parse()
let convert: Bool? = try convertFlag.parse()
let logFile: Path? = try logFileOption.parse()
// We'll use this in a minute to make sure the config is a json file (hopefully people use file extensions if creating their config manually)
let ext = (configPath.extension ?? "").lowercased()

// Try and create the Config
var config: Config
// Make sure it's a real file and it ahs the json extension
if configPath.isFile && ext == "json" {
    log.verbose("Reading config from file: \(configPath)")
    // Try and read the config from it's file
    do {
        config = try Config(configPath, logger: log)
    } catch {
        log.warning("Failed to initialize config from JSON file.")
        log.error(error)
        exit(EXIT_FAILURE)
    }
    // If an optional arg was specified, change it in the config
    if let p = plexDirectory, config.plexDirectory != p {
        log.info("Plex Directory is changing from '\(config.plexDirectory)' to '\(p)'.")
        config.plexDirectory = p
    }
    if let t = downloadDirectory, config.downloadDirectory != t {
        log.info("Download Directory is changing from '\(config.downloadDirectory)' to '\(t)'.")
        config.downloadDirectory = t
    }
    if let c = convert, config.convert != c {
        log.info("Convert is changing from '\(config.convert)' to '\(c)'.")
        config.convert = c
    }
    if let l = logFile, config.logFile != l {
        log.info("Log File is changing from '\(config.logFile)' to '\(l)'.")
        config.logFile = l
        let file = FileDestination()
        file.logFileURL = l.url
        file.minLevel = minLevel
        log.addDestination(file)
    }
} else {
    // Try and create the Config from the command line args (fails if anything is not set)
    do {
        config = try Config(configPath, plexDirectory, downloadDirectory, convert, logFile, logger: log)
        if let l = logFile {
            let file = FileDestination()
            file.logFileURL = l.url
            file.minLevel = minLevel
            log.addDestination(file)
        }
    } catch {
        log.warning("Failed to initialize config.")
        log.error(error)
        exit(EXIT_FAILURE)
    }
}
// Only log to console when we're not logging to a file or if the logLevel
//   is debug/verbose
if logLevel < 3 && logFile != nil {
    log.removeDestination(console)
}

// Try and save the config (if the flag is set to true)
if saveConfig {
    log.verbose("Saving the configuration to file.")
    do {
        try config.save()
    } catch {
        log.warning("Failed to save configuration to file.")
        log.error(error)
    }
}

// Create the monitr
monitr = Monitr(config)

// Watch for signals so we can shut down properly
Signals.trap(signals: [.int, .term, .kill, .quit]) { _ in
    log.info("Received signal. Stopping monitr.")
    monitr.shutdown()
    exit(EXIT_SUCCESS)
}

// Run once and then start monitoring regularly
log.info("Running Monitr once for startup!")
monitr.run()
monitr.setDelegate()
log.info("Monitoring '\(config.downloadDirectory)' for new files.")
monitr.startMonitoring()

let group = DispatchGroup()
group.enter()
group.wait()
