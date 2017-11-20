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

let logger = SwiftyBeaver.self

var monitr: Monitr
var arguments = CommandLine.arguments
var argParser = ArgumentParser("\(arguments.remove(at: 0)) [Options]", cliArguments: arguments)

// Args/Flags to configure this program from the CLI
let configOption = try Option<Path>("f", alternateNames: ["config"], default: Path("~/.config/monitr/settings.json"), description: "The file from which to read configuration options", required: true, parser: &argParser)
let plexDirectoryOption = try Option<Path>("p", alternateNames: ["plex-dir"], description: "The directory where the Plex libraries reside", parser: &argParser)
let downloadDirectoryOption = try Option<ArgArray<Path>>("t", alternateNames: ["download-dirs"], description: "The directory where media downloads reside", parser: &argParser)
let homeVideoDownloadDirectoryOption = try Option<ArgArray<Path>>("b", alternateNames: ["home-video-download-dirs"], description: "The directory where home video downloads reside", parser: &argParser)
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
let deleteSubtitlesFlag = try Flag("q", alternateNames: ["delete-subtitles"], description: "Whether or not external subtitle files should be deleted upon import with Monitr", parser: &argParser)
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
logger.addDestination(console)

logger.verbose("Got minimum required arguments from the CLI.")

// We'll use this in a minute to make sure the config is a json file (hopefully people use file extensions if creating their config manually)
let ext = (configPath.extension ?? "").lowercased()

// Try and create the Config
var config: Config
// Make sure it's a real file and it ahs the json extension
if configPath.isFile && ext == "json" {
    logger.verbose("Reading config from file: \(configPath)")
    // Try and read the config from it's file
    do {
        config = try Config(fromFile: configPath, with: logger)
    } catch {
        logger.warning("Failed to initialize config from JSON file.")
        logger.error(error)
        exit(EXIT_FAILURE)
    }
} else {
    config = Config(logger)
}
// If an optional arg was specified, change it in the config
if let p = plexDirectoryOption.value, config.plexDirectory != p {
    logger.info("Plex Directory is changing from '\(config.plexDirectory)' to '\(p)'.")
    config.plexDirectory = p
}
if let t = downloadDirectoryOption.value, config.downloadDirectories != t.values {
    logger.info("Download Directory is changing from '\(config.downloadDirectories)' to '\(t.values)'.")
    config.downloadDirectories = t.values
}
if let c = convertFlag.value, config.convert != c {
    logger.info("Convert is changing from '\(config.convert)' to '\(c)'.")
    config.convert = c
}
if let cI = convertImmediatelyFlag.value, config.convertImmediately != cI {
    logger.info("Convert Immediately is changing from '\(config.convertImmediately)' to '\(cI)'.")
    config.convertImmediately = cI
}
if let cCS = convertCronStartOption.value, config.convertCronStart != cCS {
    logger.info("Convert Cron Start is changing from '\(config.convertCronStart)' to '\(cCS)'.")
    config.convertCronStart = cCS
}
if let cCE = convertCronEndOption.value, config.convertCronEnd != cCE {
    logger.info("Convert Cron End is changing from '\(config.convertCronEnd)' to '\(cCE)'.")
    config.convertCronEnd = cCE
}
if let cT = convertThreadsOption.value, config.convertThreads != cT {
    logger.info("Convert Threads is changing from '\(config.convertThreads)' to '\(cT)'.")
    config.convertThreads = cT
}
if let dO = deleteOriginalFlag.value, config.deleteOriginal != dO {
    logger.info("Delete Original is changing from '\(config.deleteOriginal)' to '\(dO)'.")
    config.deleteOriginal = dO
}
if let cVC = convertVideoContainerOption.value, config.convertVideoContainer != cVC {
    logger.info("Convert Video Container is changing from '\(config.convertVideoContainer)' to '\(cVC)'.")
    config.convertVideoContainer = cVC
}
if let cVC = convertVideoCodecOption.value, config.convertVideoCodec != cVC {
    logger.info("Convert Video Codec is changing from '\(config.convertVideoCodec)' to '\(cVC)'.")
    config.convertVideoCodec = cVC
}
if let cAC = convertAudioContainerOption.value, config.convertAudioContainer != cAC {
    logger.info("Convert Audio Container is changing from '\(config.convertAudioContainer)' to '\(cAC)'.")
    config.convertAudioContainer = cAC
}
if let cAC = convertAudioCodecOption.value, config.convertAudioCodec != cAC {
    logger.info("Convert Audio Codec is changing from '\(config.convertAudioCodec)' to '\(cAC)'.")
    config.convertAudioCodec = cAC
}
if let cVSS = convertVideoSubtitleScanFlag.value, config.convertVideoSubtitleScan != cVSS {
    logger.info("Convert Video Subtitle Scan is changing from '\(config.convertVideoSubtitleScan)' to '\(cVSS)'.")
    config.convertVideoSubtitleScan = cVSS
}
if let cL = convertLanguageOption.value, config.convertLanguage != cL {
    logger.info("Convert Language is changing from '\(config.convertLanguage)' to '\(cL)'.")
    config.convertLanguage = cL
}
if let cVMF = convertVideoMaxFramerateOption.value, config.convertVideoMaxFramerate != cVMF {
    logger.info("Convert Video Max Framerate is changing from '\(config.convertVideoMaxFramerate)' to '\(cVMF)'.")
    config.convertVideoMaxFramerate = cVMF
}
if let cTD = convertTempDirectoryOption.value, config.convertTempDirectory != cTD {
    logger.info("Convert Temp Directory is changing from '\(config.convertTempDirectory)' to '\(cTD)'.")
    config.convertTempDirectory = cTD
}
if let dS = deleteSubtitlesFlag.value, config.deleteSubtitles != dS {
    logger.info("Delete Subtitles is changing from '\(config.deleteSubtitles)' to '\(dS)'.")
    config.deleteSubtitles = dS
}
if let b = homeVideoDownloadDirectoryOption.value, config.homeVideoDownloadDirectories != b.values {
    logger.info("Home Video Download Directory is changing from '\(config.homeVideoDownloadDirectories)' to '\(b.values)'.")
    config.homeVideoDownloadDirectories = b.values
}
if var lL = logLevelOption.value, config.logLevel != lL {
    // Caps logLevel to the maximum/minimum level
    if lL > 4 {
        lL = 4
    } else if lL < 0 {
        lL = 0
    }

    if lL != config.logLevel {
        logger.info("Log Level is changing from '\(config.logLevel)' to '\(lL)'.")
        config.logLevel = lL
    }
}
if let lF = logFileOption.value, config.logFile != lF {
    logger.info("Log File is changing from '\(config.logFile ?? "nil")' to '\(lF)'.")
    config.logFile = lF
}

logger.verbose("Configuration:\n\(config.printable())")

// Only log to console when we're not logging to a file or if the logLevel
//   is debug/verbose
if config.logLevel < 3 && config.logFile != nil {
    logger.removeDestination(console)
}

if let lF = config.logFile {
    let file = FileDestination()
    file.logFileURL = lF.url
    logger.addDestination(file)
}

let minLevel = SwiftyBeaver.Level(rawValue: 4 - config.logLevel)!
for dest in logger.destinations {
    dest.minLevel = minLevel
}

// Try and save the config (if the flag is set to true)
if saveConfig {
    logger.verbose("Saving the configuration to file.")
    do {
        try config.save()
    } catch {
        logger.warning("Failed to save configuration to file.")
        logger.error(error)
    }
}

// Create the monitr
do {
    monitr = try Monitr(config)
    logger.verbose("Sucessfully created the Monitr object from the config")
    
    // Run once and then start monitoring regularly
    logger.info("Running Monitr once for startup!")
    monitr.run()
    monitr.setDelegate()
    logger.info("Monitoring '\((config.downloadDirectories + config.homeVideoDownloadDirectories).map({ $0.string }))' for new files.")
    guard monitr.startMonitoring() else {
        exit(EXIT_FAILURE)
    }

    // Watch for signals so we can shut down properly
    Signals.trap(signals: [.int, .term, .kill, .quit]) { _ in
        logger.info("Received signal. Stopping monitr.")
        monitr.shutdown()
        // Sleep before exiting or else monitr may not finish shutting down before the program is exited
        sleep(1)
        exit(EXIT_SUCCESS)
    }
    
    // This keeps the program alive until ctrl-c is pressed or a signal is sent to the process
    let keepalive = AsyncGroup()
    keepalive.enter()
    keepalive.wait()
} catch {
    logger.error("Failed to create the monitr with error '\(error)'. Correct the error and try again.")
    // Sleep before exiting or else the log message is not written correctly
    sleep(1)
    exit(EXIT_FAILURE)
}
