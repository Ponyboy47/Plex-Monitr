/*

    Monitr.swift

    Created By: Jacob Williams
    Description: This file contains the Monitr class, which is used to continually check the 
                   downloads directory for new content and distribute it appropriately.
    License: MIT License

*/

import Foundation
import PathKit
import Async
import Cron
#if os(Linux)
import Dispatch
#endif

enum MonitrError: Error {
    enum MissingDependency: Error {
        case handbrake
        case mp4v2
        case ffmpeg
        case mkvtoolnix
        case transcode_video
    }
}

/// Checks the downloads directory for new content to add to Plex
final class Monitr: DirectoryMonitorDelegate {
    /// The current version of monitr
    static var version: String = "0.5.0"

    /// The configuration to use for the monitor
    private var config: Config

    /// The statistics object to track useage data for the monitor
    private var statistics: Statistic = Statistic()

    /// The queue of conversion jobs
    var conversionQueue: ConversionQueue?
    private var cronStart: CronJob?
    private var cronEnd: CronJob?

    /// Whether or not media is currently being migrated to Plex. Automatically
    ///   runs a new again if new media has been added since the run routine began
    private var isModifyingMedia: Bool = false {
        didSet {
            if !isModifyingMedia && needsUpdate {
                config.log.info("Finished moving media, but new media has already been added. Running again.")
                needsUpdate = false
                run()
            }
        }
    }
    /// If new content has been added since the run routine began
    private var needsUpdate: Bool = false

    init(_ config: Config) throws {
        self.config = config

        let statFile = config.configFile.parent + Statistic.filename
        if statFile.exists && statFile.isFile {
            self.statistics = try Statistic(statFile)
        }

        if config.convert {
            try checkConversionDependencies()
        }

        let conversionQueueFile = config.configFile.parent + ConversionQueue.filename
        if conversionQueueFile.exists && conversionQueueFile.isFile {
            self.conversionQueue = try ConversionQueue(conversionQueueFile)
        }

        if config.convert && !config.convertImmediately {
            log.info("Setting up the conversion queue cron jobs")
            self.cronStart = CronJob(pattern: config.convertCronStart, queue: .global(qos: .background)) {
                self.conversionQueue?.start()
            }
            self.cronEnd = CronJob(pattern: config.convertCronEnd, queue: .global(qos: .background)) {
                self.conversionQueue?.stop = true
            }
            let next = MediaDuration(double: cronStart!.pattern.next(Date())!.date!.timeIntervalSinceNow)
            log.info("Set up conversion cron job! It will begin in \(next.description)")
        }
    }

    private func checkConversionDependencies() throws {
		self.config.log.info("Making sure we have the required dependencies for transcoding media...") 

        // Check conversion tool dependencies 
        var dependency = "handbrake"
        let (rc1, output1) = Command.execute("which", "HandBrakeCLI")
        guard rc1 == 0, let stdout1 = output1.stdout, !stdout1.isEmpty else {
            var debugMessage = "Error determining if '\(dependency)' dependency is met.\n\tReturn Code: \(rc1)"
            if let stdout = output1.stdout {
                debugMessage += "\n\tStandard Output: '\(stdout)'"
            }
            if let stderr = output1.stderr {
                debugMessage += "\n\tStandard Error: '\(stderr)'"
            }
            self.config.log.debug(debugMessage)
            throw MonitrError.MissingDependency.handbrake 
        } 

        dependency = "mp4v2"
        let (rc2, output2) = Command.execute("which", "mp4track")
        guard rc2 == 0, let stdout2 = output2.stdout, !stdout2.isEmpty else { 
            var debugMessage = "Error determining if '\(dependency)' dependency is met.\n\tReturn Code: \(rc2)"
            if let stdout = output2.stdout {
                debugMessage += "\n\tStandard Output: '\(stdout)'"
            }
            if let stderr = output2.stderr {
                debugMessage += "\n\tStandard Error: '\(stderr)'"
            }
            self.config.log.debug(debugMessage)
            throw MonitrError.MissingDependency.mp4v2 
        } 

        dependency = "ffmpeg"
        let (rc3, output3) = Command.execute("which", "ffmpeg")
        guard rc3 == 0, let stdout3 = output3.stdout, !stdout3.isEmpty else { 
            var debugMessage = "Error determining if '\(dependency)' dependency is met.\n\tReturn Code: \(rc3)"
            if let stdout = output3.stdout {
                debugMessage += "\n\tStandard Output: '\(stdout)'"
            }
            if let stderr = output3.stderr {
                debugMessage += "\n\tStandard Error: '\(stderr)'"
            }
            self.config.log.debug(debugMessage)
            throw MonitrError.MissingDependency.ffmpeg 
        } 

        dependency = "mkvtoolnix"
        let (rc4, output4) = Command.execute("which", "mkvpropedit")
        guard rc4 == 0, let stdout4 = output4.stdout, !stdout4.isEmpty else { 
            var debugMessage = "Error determining if '\(dependency)' dependency is met.\n\tReturn Code: \(rc4)"
            if let stdout = output4.stdout {
                debugMessage += "\n\tStandard Output: '\(stdout)'"
            }
            if let stderr = output4.stderr {
                debugMessage += "\n\tStandard Error: '\(stderr)'"
            }
            self.config.log.debug(debugMessage)
            throw MonitrError.MissingDependency.mkvtoolnix 
        } 

        dependency = "transcode-video"
        let (rc5, output5) = Command.execute("which", "transcode-video")
        guard rc5 == 0, let stdout5 = output5.stdout, !stdout5.isEmpty else { 
            var debugMessage = "Error determining if '\(dependency)' dependency is met.\n\tReturn Code: \(rc5)"
            if let stdout = output5.stdout {
                debugMessage += "\n\tStandard Output: '\(stdout)'"
            }
            if let stderr = output5.stderr {
                debugMessage += "\n\tStandard Error: '\(stderr)'"
            }
            self.config.log.debug(debugMessage)
            throw MonitrError.MissingDependency.transcode_video 
        }
    }

    /// Gets all media object and moves them to Plex then deletes all the empty
    ///   directories left in the downloads directory
    public func run() {
        // Set that we're modifying the media as long as we're still contained in the run function
        self.isModifyingMedia = true
        // Unset the isModifyingMedia as soon as the run function completes
        defer {
            // Removes all empty directories from the download directory
            self.cleanup(dir: self.config.downloadDirectory)
            self.isModifyingMedia = false
        }
        // Get all the media in the downloads directory
        var media = self.getAllMedia(from: self.config.downloadDirectory)

        guard media.count > 0 else {
            self.config.log.info("No media found.")
            return
        }

        let video = media.filter { $0 is Video }
        let audio = media.filter { $0 is Audio }
        let other = media.filter { $0 is Ignore }

        self.config.log.info("Found \(media.count) files in the download directory!")
        if video.count > 0 {
            self.config.log.info("\t \(video.count) video files")
            self.config.log.verbose(video.map { $0.path })
        }
        if audio.count > 0 {
            self.config.log.info("\t \(audio.count) audio files")
            self.config.log.verbose(audio.map { $0.path })
        }
        if other.count > 0 {
            self.config.log.info("\t \(other.count) other files")
            self.config.log.verbose(other.map { $0.path })
        }

        // If we want to convert media, lets do that before we move it to plex
        //   NOTE: If convertImmediately is false, then a queue of conversion 
        //         jobs are created to be run during the scheduled time period
        if self.config.convert, let unconvertedMedia = self.convertMedia(&media) {
            self.config.log.warning("Failed to convert media:\n\t\(unconvertedMedia.map({ $0.path }))")
        }

        // If we gathered any supported media files, move them to their plex location
        if let unmovedMedia = self.moveMedia(&media) {
            self.config.log.warning("Failed to move media to plex:\n\t\(unmovedMedia.map({ $0.path }))")
        }
    }

    /// Sets the delegate for the downloads directory monitor
    public func setDelegate() {
        self.config.setDelegate(self)
    }

    /// Begin watching the downloads directory
    @discardableResult
    public func startMonitoring() -> Bool {
        return self.config.startMonitoring()
    }

    /**
     Stop watching the downloads directory

     - Parameter now: If true, kills any active media management. Defaults to false
    */
    public func shutdown(now: Bool = false) {
        self.config.log.info("Shutting down monitr.")
        self.config.stopMonitoring()
        self.config.log.info("Saving the program's statistics")
        try? self.statistics.save(self.config.configFile.parent)
        if (self.conversionQueue?.waiting ?? 0) > 0 {
            self.config.log.info("Saving conversion queue")
            try? self.conversionQueue?.save()
        }
        // Go through conversions and halt them/save them
        if now {
            // Kill any other stuff going on
            if (self.conversionQueue?.active ?? 0) > 0 {
                // TODO: Kill and cleanup current conversion jobs
            }
        } else {
            if (self.conversionQueue?.active ?? 0) > 0 {
                self.conversionQueue?.stop = true
                self.config.log.info("Waiting for current conversion jobs to finish before shutting down")
                self.conversionQueue?.conversionGroup.wait()
            }
        }
    }

    /**
     Gets all the supported Plex media files from the path

     - Parameter from: The path to recursively search through for supported media

     - Returns: An array of the supported media files found
    */
    func getAllMedia(from path: Path) -> [Media] {
        do {
            // Get all the children in the downloads directory
            let children = try path.recursiveChildren()
            var media: [Media] = []
            // Iterate of the children paths
            // Skips the directories and just checks for files
            for childFile in children where childFile.isFile {
                if let m = self.getMedia(with: childFile) {
                    media.append(m)
                } else {
                    self.config.log.warning("Unknown/unsupported file found: \(childFile)")
                }
            }
            return media
        } catch {
            self.config.log.warning("Failed to get recursive children from the downloads directory.")
            self.config.log.error(error)
        }
        return []
    }

    /**
     Returns a media object if the file is one of the supported formats

     - Parameter with: The path to the file from which to create a Media object

     - Returns: A Media object, or nil if the file is not supported
    */
    private func getMedia(with file: Path) -> Media? {
		let ext = file.extension ?? ""
        do {
            if Video.isSupported(ext: ext) {
                do {
                    let video = try Video(file)
                    video.findSubtitles(below: self.config.downloadDirectory, log: self.config.log)
                    return video
                } catch MediaError.VideoError.sampleMedia {
                    return try Ignore(file)
                }
            } else if Audio.isSupported(ext: ext) {
                return try Audio(file)
            } else if Ignore.isSupported(ext: ext) || file.string.lowercased().ends(with: ".ds_store") {
                return try Ignore(file)
            }
        } catch {
            self.config.log.warning("Error occured trying to create media object from '\(file)'.")
            self.config.log.error(error)
        }
        return nil
    }

    /**
     Moves the array of Media objects to their proper locations in the Plex Library

     - Parameter media: The array of Media objects to move

     - Returns: An array of Media objects that failed to move
    */
    func moveMedia(_ media: inout [Media]) -> [Media]? {
        var failedMedia: [Media] = []

        for var m in media {
            // Starts a new utility thread to move the file
            Sync.utility {
                self.statistics.measure(.move) {
                    do {
                        m = try m.move(to: self.config.plexDirectory, log: self.config.log)
                        if self.config.deleteSubtitles && m is Video {
                            m = try (m as! Video).deleteSubtitles() as Media
                        }
                    } catch {
                        self.config.log.warning("Failed to move media: \(m.path)")
                        self.config.log.error(error)
                        failedMedia.append(m)
                    }
                }
            }
        }

        guard failedMedia.count > 0 else { return nil }

        return failedMedia
    }

    /**
     Converts the array of Media object to convert to Plex DirectPlay supported formats

     - Parameter media: The array of Media objects to convert

     - Returns: An array of Media objects that failed to be converted
    */
    func convertMedia(_ media: inout [Media]) -> [ConvertibleMedia]? {
        var failedMedia: [ConvertibleMedia] = []

        let videoConfig = VideoConversionConfig(container: self.config.convertVideoContainer, videoCodec: self.config.convertVideoCodec, audioCodec: self.config.convertAudioCodec, subtitleScan: self.config.convertVideoSubtitleScan, mainLanguage: self.config.convertLanguage, maxFramerate: self.config.convertVideoMaxFramerate, plexDir: self.config.plexDirectory, tempDir: self.config.deleteOriginal ? nil : self.config.convertTempDirectory)
        let audioConfig = AudioConversionConfig(container: self.config.convertAudioContainer, codec: self.config.convertAudioCodec, plexDir: self.config.plexDirectory, tempDir: self.config.deleteOriginal ? nil : self.config.convertTempDirectory)

        self.config.log.info("Getting the array of media that needs to be converted.")
        let mediaToConvert: [ConvertibleMedia] = media.filter {
            guard $0 is ConvertibleMedia else { return false }
            if $0 is Video {
                do {
                    guard try Video.needsConversion(file: $0.path, with: videoConfig, log: self.config.log) else { return false }
                } catch {}
                log.info("We must convert video file '\($0.path.absolute)' for Plex Direct Play/Stream.")
                return true
            } else if  $0 is Audio {
                do {
                    guard try Audio.needsConversion(file: $0.path, with: audioConfig, log: self.config.log) else { return false }
                } catch {}
                log.info("We must convert audio file '\($0.path.absolute)' for Plex Direct Play/Stream.")
                return true
            }
            return false
            } as! [ConvertibleMedia]

        if self.config.convertImmediately {
            self.config.log.verbose("Converting media immediately")

            let convertGroup = AsyncGroup()
            var simultaneousConversions: Int = 0
            for var m in mediaToConvert {
                if m is Video {
                    simultaneousConversions += 1
                    convertGroup.utility {
                        self.statistics.measure(.convert) {
                            do {
                                m = try m.convert(videoConfig, self.config.log)
                            } catch {
                                self.config.log.warning("Failed to convert video file: \(m.path)")
                                self.config.log.error(error)
                                failedMedia.append(m)
                            }
                        }
                        simultaneousConversions -= 1
                    }
                } else if m is Audio {
                    simultaneousConversions += 1
                    convertGroup.utility {
                        self.statistics.measure(.convert) {
                            do {
                                m = try m.convert(audioConfig, self.config.log)
                            } catch {
                                self.config.log.warning("Failed to convert audio file: \(m.path)")
                                self.config.log.error(error)
                                failedMedia.append(m)
                            }
                        }
                        simultaneousConversions -= 1
                    }
                }
                self.config.log.verbose("Currently running \(simultaneousConversions) simultaneous conversion jobs.")

                // Check to see if we've started all the conversion jobs now
                var isLast = false

                // If the current media object is the same as the last one, then we can compare them. If they're different then we know they're not a match anyways
                if m is Video && mediaToConvert.last is Video {
                    isLast = m.path == mediaToConvert.last!.path
                } else if m is Audio && mediaToConvert.last is Audio {
                    isLast = m.path == mediaToConvert.last!.path
                }
                if !isLast {
                    // Blocks for as long as there are as many conversion jobs
                    // running as the configured conversion thread limit
                    //   NOTE: Does this by waiting for 60 seconds (or until all
                    //   threads have completed) and then rechecking the number of
                    //   simultaneous conversions (since the number should
                    //   increment when a thread starts and decrement when it
                    //   finishes)
                    while simultaneousConversions >= self.config.convertThreads {
                        self.config.log.info("Maximum number conversion threads (\(self.config.convertThreads)) reached. Waiting 60 seconds and checking to see if any have finished.")
                        convertGroup.wait(seconds: 60)
                    }
                }
            }
            // Now that we've started all the conversion processes, wait indefinitely for them all to finish
            convertGroup.wait()
        } else {
            if self.conversionQueue == nil {
                self.config.log.info("Creating a conversion queue")
                self.conversionQueue = ConversionQueue(self.config, statistics: self.statistics)
            } else {
                self.config.log.info("Using existing conversion queue")
            }

            // Create a queue of conversion jobs for later
            for var m in mediaToConvert {
                self.conversionQueue!.push(&m)
            }
        }

        guard failedMedia.count > 0 else { return nil }

        return failedMedia
    }

    /**
     Recursively cleans all empty directories at the path

     - Parameter dir: The directory to recursively search through and clean up
    */
    func cleanup(dir: Path) {
        do {
            let children = try dir.children()
            guard children.count > 0 else {
                guard dir != config.downloadDirectory else { return }
                do {
                    try dir.delete()
                } catch {
                    config.log.warning("Failed to delete directory '\(dir)'.")
                    config.log.error(error)
                }
                return
            }
            for childDirectory in children where childDirectory.isDirectory {
                cleanup(dir: childDirectory)
            }
        } catch {
            config.log.warning("Failed to get the '\(dir)' directory's children.")
            config.log.error(error)
        }
    }

    // MARK: - DirectorMonitor delegate method(s)

    /**
     Called when an event is triggered by the directory monitor

     - Parameter directoryMonitor: The DirectoryMonitor that triggered the event
    */
    func directoryMonitorDidObserveChange(_ directoryMonitor: DirectoryMonitor) {
        // The FileSystem monitoring doesn't work on Linux yet, so only check
        //   if a write occurred in the directory if we're not on Linux
        #if !os(Linux)
        // Check that a new write occured
        guard directoryMonitor.directoryMonitorSource?.data == .write else {
            needsUpdate = false
            return
        }
        #endif
        // Make sure we're not already modifying media, otherwise just set the
        //   needsUpdate variable so that it's run again once it finishes
        guard !isModifyingMedia else {
            config.log.info("Currently moving media. Will move new media after the current operation is completed.")
            needsUpdate = true
            return
        }
        run()
    }
}
