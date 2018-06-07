/*

    main.swift

    Created By: Jacob Williams
    Description: This is the main source file that will set up the config and
                   start the monitoring
    License: MIT License

*/

import Foundation
import Dispatch
import SwiftyBeaver
import PathKit
import Signals
import Cron
import CLI
import LockSmith

// For sleep() and exit()
#if os(Linux)
import Glibc
#else
import Darwin
#endif

// Locks the current swift process
var processLock = LockSmith.singleton

// Makes sure LockSmith succeeded at locking the process
guard processLock != nil else {
    print("Failed to lock process. Does another instance of \(ProcessInfo.processInfo.processName) already exist?")
    exit(EXIT_FAILURE)
}

let logger = SwiftyBeaver.self

var argParser = ArgumentParser.default

// Disable the line_length linting since just about all of these surpass the limit
// swiftlint:disable line_length
// swiftlint:disable identifier_name

// Args/Flags to configure this program from the CLI
let configOption = try Option<Path>("f", "config", default: Path("~/.config/monitr/settings.json"), description: "The file from which to read configuration options", required: true, parser: &argParser)
let plexDirectoryOption = try Option<Path>("p", "plex-dir", description: "The directory where the Plex libraries reside", parser: &argParser)
let downloadDirectoryOption = try Option<ArgArray<Path>>("d", "download-dirs", description: "The directory where media downloads reside", parser: &argParser)
let homeVideoDownloadDirectoryOption = try Option<ArgArray<Path>>("home-video-download-dirs", description: "The directory where home video downloads reside", parser: &argParser)
let convertFlag = try Flag("c", "convert", description: "Whether or not newly added files should be converted to a Plex DirectPlay format", parser: &argParser)
let convertImmediatelyFlag = try Flag("i", "convert-immediately", description: "Whether to convert media before sending it to the Plex directory, or to convert it as a scheduled task when the CPU is more likely to be free", parser: &argParser)
let convertCronStartOption = try Option<DatePattern>("a", "convert-cron-start", description: "A Cron string describing when conversion jobs should start running", parser: &argParser)
let convertCronEndOption = try Option<DatePattern>("z", "convert-cron-end", description: "A Cron string describing when conversion jobs should stop running", parser: &argParser)
let convertThreadsOption = try Option<Int>("convert-threads", description: "The number of threads that can simultaneously be converting media", parser: &argParser)
let deleteOriginalFlag = try Flag("delete-original", description: "Whether the original media file should be deleted upon successful conversion to a Plex DirectPlay format", parser: &argParser)
let convertABRFlag = try Flag("abr", "average-bitrate-rcs", description: "Whether to use the default or the Constrained Average Bitrate (ABR) ratecontrol system in transcode_video", parser: &argParser)
let convertH265Flag = try Flag("h265", description: "Whether to use the h265 encoder instead of the h264 encoder", parser: &argParser)
let convertTargetOption = try MultiOption<Target>("t", "target", description: "The transcode_video target to use when converting video", parser: &argParser)
let convertSpeedOption = try Option<TranscodeSpeed>("speed", "transcode-speed", description: "Which speed to use when transcoding media", parser: &argParser)
let convertX264PresetOption = try Option<X264Preset>("x264-preset", description: "Which x264 codec speed preset to use when transcoding media", parser: &argParser)
let convertVideoContainerOption = try Option<VideoContainer>("convert-video-container", description: "The container to use when converting video files", parser: &argParser)
let convertVideoCodecOption = try Option<VideoCodec>("convert-video-codec", description: "The codec to use when converting video streams. Setting to 'any' will allow Plex to just use DirectStream instead of DirectPlay and only have to transcode the video stream on the fly", parser: &argParser)
let convertAudioContainerOption = try Option<AudioContainer>("convert-audio-container", description: "The container to use when converting audio files", parser: &argParser)
let convertAudioCodecOption = try Option<AudioCodec>("convert-audio-codec", description: "The codec to use when converting audio streams. Setting to 'any' will allow Plex to just use DirectStream instead of DirectPlay and only have to transcode the audio stream on the fly", parser: &argParser)
let convertVideoSubtitleScanFlag = try Flag("convert-video-subtitle-scan", description: "Whether to scan media file streams and forcefully burn subtitles for foreign audio.\n\t\tNOTE: This is experimental in transcode_video and is not guarenteed to work 100% of the time. In fact, when it doesn't work, it will probably burn in the wrong language. It is recomended to never use this in conjunction with the --delete-original option", parser: &argParser)
let convertLanguageOption = try Option<Language>("convert-language", description: "The main language to select when converting media with multiple languages available", parser: &argParser)
let convertVideoMaxFramerateOption = try Option<Double>("convert-video-max-framerate", description: "The maximum framerate limit to use when converting video files", parser: &argParser)
let convertTempDirectoryOption = try Option<Path>("convert-temp-dir", description: "The directory where converted media will go prior to being moved to plex", parser: &argParser)
let deleteSubtitlesFlag = try Flag("delete-subtitles", description: "Whether or not external subtitle files should be deleted upon import with Monitr", parser: &argParser)
let saveFlag = try Flag("s", "save-settings", default: false, description: "Whether or not the configured settings should be saved to the config options file", required: true, parser: &argParser)
let logLevelOption = try Option<SwiftyBeaver.Level>("level", "log-level", description: "The logging level to use (verbose, debug, info, warn, error)", parser: &argParser)
let logFileOption = try Option<Path>("o", "log-file", description: "Where to write the log file.", parser: &argParser)

// Re-enable the line_length checks now
// swiftlint:enable line_length

// Sets the values of all the arguments
try argParser.parseAll()

// Prints the help/usage text if -h or --help was used
guard !argParser.needsHelp else {
    argParser.printHelp()
    exit(EXIT_SUCCESS)
}

guard !argParser.wantsVersion else {
    print(MainMonitr.version)
    exit(EXIT_SUCCESS)
}

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
    logger.verbose("Creating new config from scratch using the defaults")
}

let commonMsg: String
if !saveConfig {
    commonMsg = "is temporarily changing from"
} else {
    commonMsg = "is being modified from"
}

// If an optional arg was specified, change it in the config
if let p = plexDirectoryOption.value, config.plexDirectory != p {
    logger.debug("PlexDirectory \(commonMsg) \(config.plexDirectory) to \(p)")
    config.plexDirectory = p
}
if let t = downloadDirectoryOption.value, config.downloadDirectories != t.values {
    logger.debug("Download Directory \(commonMsg) '\(config.downloadDirectories)' to '\(t.values)'.")
    config.downloadDirectories = t.values
}
if let c = convertFlag.value, config.convert != c {
    logger.debug("Convert \(commonMsg) '\(config.convert)' to '\(c)'.")
    config.convert = c
}
if let cI = convertImmediatelyFlag.value, config.convertImmediately != cI {
    logger.debug("Convert Immediately \(commonMsg) '\(config.convertImmediately)' to '\(cI)'.")
    config.convertImmediately = cI
}
if let cCS = convertCronStartOption.value, config.convertCronStart != cCS {
    logger.debug("Convert Cron Start \(commonMsg) '\(config.convertCronStart)' to '\(cCS)'.")
    config.convertCronStart = cCS
}
if let cCE = convertCronEndOption.value, config.convertCronEnd != cCE {
    logger.debug("Convert Cron End \(commonMsg) '\(config.convertCronEnd)' to '\(cCE)'.")
    config.convertCronEnd = cCE
}
if let cT = convertThreadsOption.value, config.convertThreads != cT {
    logger.debug("Convert Threads \(commonMsg) '\(config.convertThreads)' to '\(cT)'.")
    config.convertThreads = cT
}
if let dO = deleteOriginalFlag.value, config.deleteOriginal != dO {
    logger.debug("Delete Original \(commonMsg) '\(config.deleteOriginal)' to '\(dO)'.")
    config.deleteOriginal = dO
}
if let abr = convertABRFlag.value, config.convertABR != abr {
    logger.debug("Convert ABR \(commonMsg) '\(config.convertABR)' to '\(abr)'.")
    config.convertABR = abr
}
if let h265 = convertH265Flag.value, config.convertH265 != h265 {
    logger.debug("Convert 265 \(commonMsg) '\(config.convertH265)' to '\(h265)'.")
    config.convertH265 = h265
}
do {
    repeat {
        if let cT = convertTargetOption.value {
            if !config.convertTargets.contains(cT) {
                logger.debug("Appending Convert Target \(cT) to config")
                config.convertTargets.append(cT)
            }
        } else { break }
    } while true
}
if let speed = convertSpeedOption.value, config.convertSpeed != speed {
    logger.debug("Convert Speed \(commonMsg) '\(config.convertSpeed)' to '\(speed)'.")
    config.convertSpeed = speed
}
if let preset = convertX264PresetOption.value, config.convertX264Preset != preset {
    logger.debug("Convert X264 Preset \(commonMsg) '\(config.convertX264Preset)' to '\(preset)'.")
    config.convertX264Preset = preset
}
if let cVC = convertVideoContainerOption.value, config.convertVideoContainer != cVC {
    logger.debug("Convert Video Container \(commonMsg) '\(config.convertVideoContainer)' to '\(cVC)'.")
    config.convertVideoContainer = cVC
}
if let cVC = convertVideoCodecOption.value, config.convertVideoCodec != cVC {
    logger.debug("Convert Video Codec \(commonMsg) '\(config.convertVideoCodec)' to '\(cVC)'.")
    config.convertVideoCodec = cVC
}
if let cAC = convertAudioContainerOption.value, config.convertAudioContainer != cAC {
    logger.debug("Convert Audio Container \(commonMsg) '\(config.convertAudioContainer)' to '\(cAC)'.")
    config.convertAudioContainer = cAC
}
if let cAC = convertAudioCodecOption.value, config.convertAudioCodec != cAC {
    logger.debug("Convert Audio Codec \(commonMsg) '\(config.convertAudioCodec)' to '\(cAC)'.")
    config.convertAudioCodec = cAC
}
if let cVSS = convertVideoSubtitleScanFlag.value, config.convertVideoSubtitleScan != cVSS {
    logger.debug("Convert Video Subtitle Scan \(commonMsg) '\(config.convertVideoSubtitleScan)' to '\(cVSS)'.")
    config.convertVideoSubtitleScan = cVSS
}
if let cL = convertLanguageOption.value, config.convertLanguage != cL {
    logger.debug("Convert Language \(commonMsg) '\(config.convertLanguage)' to '\(cL)'.")
    config.convertLanguage = cL
}
if let cVMF = convertVideoMaxFramerateOption.value, config.convertVideoMaxFramerate != cVMF {
    logger.debug("Convert Video Max Framerate \(commonMsg) '\(config.convertVideoMaxFramerate)' to '\(cVMF)'.")
    config.convertVideoMaxFramerate = cVMF
}
if let cTD = convertTempDirectoryOption.value, config.convertTempDirectory != cTD {
    logger.debug("Convert Temp Directory \(commonMsg) '\(config.convertTempDirectory)' to '\(cTD)'.")
    config.convertTempDirectory = cTD
}
if let dS = deleteSubtitlesFlag.value, config.deleteSubtitles != dS {
    logger.debug("Delete Subtitles \(commonMsg) '\(config.deleteSubtitles)' to '\(dS)'.")
    config.deleteSubtitles = dS
}
if let b = homeVideoDownloadDirectoryOption.value, config.homeVideoDownloadDirectories != b.values {
    logger.debug("Home Video Download Directory \(commonMsg) '\(config.homeVideoDownloadDirectories)' to '\(b.values)'.")
    config.homeVideoDownloadDirectories = b.values
}
if let lL = logLevelOption.value, config.logLevel != lL {
    if lL != config.logLevel {
        logger.debug("Log Level \(commonMsg) '\(config.logLevel)' to '\(lL)'.")
        config.logLevel = lL
    }
}
if let lF = logFileOption.value, config.logFile != lF {
    logger.debug("Log File \(commonMsg) '\(config.logFile ?? "nil")' to '\(lF)'.")
    config.logFile = lF
}

logger.info("Configuration:\n\(config.printable())")

// Only log to console when we're not logging to a file or if the logLevel
//   is debug/verbose
if config.logLevel > 1 && config.logFile != nil {
    logger.removeDestination(console)
}

if let lF = config.logFile {
    let file = FileDestination()
    file.logFileURL = lF.url
    logger.addDestination(file)
}

for dest in logger.destinations {
    dest.minLevel = config.logLevel
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

let mainMonitr: MainMonitr

// Create the monitrs
do {
    mainMonitr = try MainMonitr(config: config)
    logger.verbose("Sucessfully created the Monitr objects from the config")
    mainMonitr.setDelegate()
    guard mainMonitr.startMonitoring() else {
        logger.error("Failed to start monitoring the download directories for new files")
        exit(EXIT_FAILURE)
    }

    logger.info("Monitoring '\((config.downloadDirectories + config.homeVideoDownloadDirectories).map({ $0.string }))' for new files.")

    // Watch for signals so we can shut down properly
    Signals.trap(signals: [.int, .term, .kill, .quit]) { _ in
        logger.info("Received signal. Stopping monitr.")
        // deinitializes the processLock, which unlocks any and all locks
        processLock = nil
        mainMonitr.shutdown()
        // Sleep before exiting or else monitr may not finish shutting down before the program is exited
        sleep(1)
        exit(EXIT_SUCCESS)
    }

    // Run once in case there are files already in the directories
    mainMonitr.run()

    // This keeps the program alive until ctrl-c is pressed or a signal is sent to the process
    let keepalive = DispatchGroup()
    keepalive.enter()
    keepalive.wait()
} catch {
    logger.error("Failed to create the monitrs with error '\(error)'. Correct the error and try again.")
    // Sleep before exiting or else the log message is not written correctly
    sleep(1)
    exit(EXIT_FAILURE)
}
