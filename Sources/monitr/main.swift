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
import Cron
import CLI
import Async
#if os(Linux)
import Glibc
#else
import Darwin
#endif

let log = SwiftyBeaver.self

var monitr: Monitr
var arguments = CommandLine.arguments
var argParser = ArgumentParser("\(arguments.remove(at: 0)) [Options]", cliArguments: arguments)

// Args/Flags to configure this program from the CLI
let configOption = try Option<Path>("f", alternateNames: ["config"], default: Path("~/.config/monitr/settings.json"), description: "The file from which to read configuration options", required: true, parser: &argParser)
let plexDirectoryOption = try Option<Path>("p", alternateNames: ["plex-dir"], description: "The directory where the Plex libraries reside", parser: &argParser)
let downloadDirectoryOption = try Option<Path>("t", alternateNames: ["download-dir"], description: "The directory where media downloads reside", parser: &argParser)
let convertFlag = try Flag("c", alternateNames: ["convert"], description: "Whether or not newly added files should be converted to a Plex DirectPlay format", parser: &argParser)
let convertImmediatelyFlag = try Flag("i", alternateNames: ["convert-immediately"], description: "Whether to convert media before sending it to the Plex directory, or to convert it as a scheduled task when the CPU is more likely to be free", parser: &argParser)
let convertCronStartOption = try Option<DatePattern>("a", alternateNames: ["convert-cron-start"], description: "A Cron string describing when conversion jobs should start running", parser: &argParser)
let convertCronEndOption = try Option<DatePattern>("z", alternateNames: ["convert-cron-end"], description: "A Cron string describing when conversion jobs should stop running", parser: &argParser)
let convertThreadsOption = try Option<Int>("r", alternateNames: ["convert-threads"], description: "The number of threads that can simultaneously be converting media", parser: &argParser)
let deleteOriginalFlag = try Flag("o", alternateNames: ["delete-original"], description: "Whether the original media file should be deleted upon successful conversion to a Plex DirectPlay format", parser: &argParser)
let convertVideoContainerOption = try Option<VideoContainer>("e", alternateNames: ["convert-video-container"], description: "The container to use when converting video files", parser: &argParser)
let convertVideoCodecOption = try Option<VideoCodec>("g", alternateNames: ["convert-video-codec"], description: "The codec to use when converting video streams. Setting to 'any' will allow Plex to just use DirectStream instead of DirectPlay and only have to transcode the video stream on the fly", parser: &argParser)
let convertAudioContainerOption = try Option<AudioContainer>("j", alternateNames: ["convert-audio-container"], description: "The container to use when converting audio files", parser: &argParser)
let convertAudioCodecOption = try Option<AudioCodec>("k", alternateNames: ["convert-audio-codec"], description: "The codec to use when converting audio streams. Setting to 'any' will allow Plex to just use DirectStream instead of DirectPlay and only have to transcode the audio stream on the fly", parser: &argParser)
let convertVideoSubtitleScanFlag = try Flag("n", alternateNames: ["convert-video-subtitle-scan"], description: "Whether to scan media file streams and forcefully burn subtitles for foreign audio.\n\t\tNOTE: This is experimental in transcode_video and is not guarenteed to work 100% of the time. In fact, when it doesn't work, it will probably burn in the wrong language. It is recomended to never use this in conjunction with the --delete-original option", parser: &argParser)
let convertLanguageOption = try Option<Language>("l", alternateNames: ["convert-language"], description: "The main language to select when converting media with multiple languages available", parser: &argParser)
let convertVideoMaxFramerateOption = try Option<Double>("m", alternateNames: ["convert-video-max-framerate"], description: "The maximum framerate limit to use when converting video files", parser: &argParser)
let convertTempDirectoryOption = try Option<Path>("u", alternateNames: ["convert-temp-dir"], description: "The directory where converted media will go prior to being moved to plex", parser: &argParser)
let saveFlag = try Flag("s", alternateNames: ["save-settings"], default: false, description: "Whether or not the configured settings should be saved to the config options file", required: true, parser: &argParser)
let logLevelOption = try Option<Int>("d", alternateNames: ["log-level"], description: "The logging level to use. Higher numbers mean more logging. Valid number range is 0-4.", parser: &argParser)
let logFileOption = try Option<Path>("l", alternateNames: ["log-file"], description: "Where to write the log file.", parser: &argParser)

// Prints the help/usage text if -h or --help was used
guard !argParser.needsHelp else {
    argParser.printHelp()
    exit(EXIT_SUCCESS)
}

guard !argParser.wantsVersion else {
    print(Monitr.version)
    exit(EXIT_SUCCESS)
}

// Sets the values of all the arguments
try argParser.parse()

guard let configPath: Path = configOption.value else {
    print("Something went wrong and the configPath option was not set")
    exit(EXIT_FAILURE)
}
guard let saveConfig: Bool = saveFlag.value else {
    print("Something went wrong and the save flag was not set")
    exit(EXIT_FAILURE)
}

let console = ConsoleDestination()
log.addDestination(console)

log.verbose("Got minimum required arguments from the CLI.")

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
    if let p = plexDirectoryOption.value, config.plexDirectory != p {
        log.info("Plex Directory is changing from '\(config.plexDirectory)' to '\(p)'.")
        config.plexDirectory = p
    }
    if let t = downloadDirectoryOption.value, config.downloadDirectory != t {
        log.info("Download Directory is changing from '\(config.downloadDirectory)' to '\(t)'.")
        config.downloadDirectory = t
    }
    if let c = convertFlag.value, config.convert != c {
        log.info("Convert is changing from '\(config.convert)' to '\(c)'.")
        config.convert = c
    }
    if let cI = convertImmediatelyFlag.value, config.convertImmediately != cI {
        log.info("Convert Immediately is changing from '\(config.convertImmediately)' to '\(cI)'.")
        config.convertImmediately = cI
    }
    if let cCS = convertCronStartOption.value, config.convertCronStart != cCS {
        log.info("Convert Cron Start is changing from '\(config.convertCronStart)' to '\(cCS)'.")
        config.convertCronStart = cCS
    }
    if let cCE = convertCronEndOption.value, config.convertCronEnd != cCE {
        log.info("Convert Cron End is changing from '\(config.convertCronEnd)' to '\(cCE)'.")
        config.convertCronEnd = cCE
    }
    if let cT = convertThreadsOption.value, config.convertThreads != cT {
        log.info("Convert Threads is changing from '\(config.convertThreads)' to '\(cT)'.")
        config.convertThreads = cT
    }
    if let dO = deleteOriginalFlag.value, config.deleteOriginal != dO {
        log.info("Delete Original is changing from '\(config.deleteOriginal)' to '\(dO)'.")
        config.deleteOriginal = dO
    }
    if let cVC = convertVideoContainerOption.value, config.convertVideoContainer != cVC {
        log.info("Convert Video Container is changing from '\(config.convertVideoContainer)' to '\(cVC)'.")
        config.convertVideoContainer = cVC
    }
    if let cVC = convertVideoCodecOption.value, config.convertVideoCodec != cVC {
        log.info("Convert Video Codec is changing from '\(config.convertVideoCodec)' to '\(cVC)'.")
        config.convertVideoCodec = cVC
    }
    if let cAC = convertAudioContainerOption.value, config.convertAudioContainer != cAC {
        log.info("Convert Audio Container is changing from '\(config.convertAudioContainer)' to '\(cAC)'.")
        config.convertAudioContainer = cAC
    }
    if let cAC = convertAudioCodecOption.value, config.convertAudioCodec != cAC {
        log.info("Convert Audio Codec is changing from '\(config.convertAudioCodec)' to '\(cAC)'.")
        config.convertAudioCodec = cAC
    }
    if let cVSS = convertVideoSubtitleScanFlag.value, config.convertVideoSubtitleScan != cVSS {
        log.info("Convert Video Subtitle Scan is changing from '\(config.convertVideoSubtitleScan)' to '\(cVSS)'.")
        config.convertVideoSubtitleScan = cVSS
    }
    if let cL = convertLanguageOption.value, config.convertLanguage != cL {
        log.info("Convert Language is changing from '\(config.convertLanguage)' to '\(cL)'.")
        config.convertLanguage = cL
    }
    if let cVMF = convertVideoMaxFramerateOption.value, config.convertVideoMaxFramerate != cVMF {
        log.info("Convert Video Max Framerate is changing from '\(config.convertVideoMaxFramerate)' to '\(cVMF)'.")
        config.convertVideoMaxFramerate = cVMF
    }
    if let cTD = convertTempDirectoryOption.value, config.convertTempDirectory != cTD {
        log.info("Convert Temp Directory is changing from '\(config.convertTempDirectory)' to '\(cTD)'.")
        config.convertTempDirectory = cTD
    }
    if var lL = logLevelOption.value, config.logLevel != lL {
        // Caps logLevel to the maximum/minimum level
        if lL > 4 {
            lL = 4
        } else if lL < 0 {
            lL = 0
        }

        if lL != config.logLevel {
            log.info("Log Level is changing from '\(config.logLevel)' to '\(lL)'.")
            config.logLevel = lL
        }
    }
    if let lF = logFileOption.value, config.logFile != lF {
        log.info("Log File is changing from '\(config.logFile ?? "nil")' to '\(lF)'.")
        config.logFile = lF
    }
} else {
    // Try and create the Config from the command line args (fails if anything is not set)
    do {
        config = try Config(configPath, plexDirectoryOption.value, downloadDirectoryOption.value, convertFlag.value, convertImmediatelyFlag.value, convertCronStartOption.value, convertCronEndOption.value, convertThreadsOption.value, deleteOriginalFlag.value, convertVideoContainerOption.value, convertVideoCodecOption.value, convertAudioContainerOption.value, convertAudioCodecOption.value, convertVideoSubtitleScanFlag.value, convertLanguageOption.value, convertVideoMaxFramerateOption.value, convertTempDirectoryOption.value, logLevelOption.value, logFileOption.value, logger: log)
    } catch {
        log.warning("Failed to initialize config.")
        log.error(error)
        exit(EXIT_FAILURE)
    }
}

log.verbose("Configuration:\n\(config.printable())")

// Only log to console when we're not logging to a file or if the logLevel
//   is debug/verbose
if config.logLevel < 3 && config.logFile != nil {
    log.removeDestination(console)
}

if let lF = config.logFile {
    let file = FileDestination()
    file.logFileURL = lF.url
    log.addDestination(file)
}

let minLevel = SwiftyBeaver.Level(rawValue: 4 - config.logLevel)!
for var dest in log.destinations {
    dest.minLevel = minLevel
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
do {
    monitr = try Monitr(config)
    log.verbose("Sucessfully created the Monitr object from the config")

    let keepalive = AsyncGroup()

    func schedule(pattern: DatePattern, group: AsyncGroup = keepalive, job: @escaping @convention(block) () -> ()) {
        guard let next = pattern.next()?.date else {
            print("No next execution date could be determined")
            return
        }

        let interval = next.timeIntervalSinceNow
        group.enter()
        sleep(UInt32(interval))
        job()
        group.leave()
        schedule(pattern: pattern, group: group, job: job)
    }

    if config.convert && !config.convertImmediately {
        log.info("Setting up the conversion queue cron jobs")
        schedule(pattern: config.convertCronStart, job: {
            monitr.conversionQueue?.start()
        })
        schedule(pattern: config.convertCronEnd, job: {
            monitr.conversionQueue?.stop = true
        })
        let next = MediaDuration(double: config.convertCronStart.next(Date())!.date!.timeIntervalSinceNow)
        log.info("Set up conversion cron job! It will begin in \(next.description)")
    }
    
    // Run once and then start monitoring regularly
    log.info("Running Monitr once for startup!")
    monitr.run()
    monitr.setDelegate()
    log.info("Monitoring '\(config.downloadDirectory)' for new files.")
    guard monitr.startMonitoring() else {
        exit(EXIT_FAILURE)
    }

    // Watch for signals so we can shut down properly
    Signals.trap(signals: [.int, .term, .kill, .quit]) { _ in
        log.info("Received signal. Stopping monitr.")
        monitr.shutdown()
        // Sleep before exiting or else monitr may not finish shutting down before the program is exited
        sleep(1)
        exit(EXIT_SUCCESS)
    }
    
    // This keeps the program alive until ctrl-c is pressed or a signal is sent to the process
    keepalive.enter()
    keepalive.wait()
} catch {
    log.error("Failed to create the monitr with error '\(error)'. Correct the error and try again.")
    // Sleep before exiting or else the log message is not written correctly
    sleep(1)
    exit(EXIT_FAILURE)
}
