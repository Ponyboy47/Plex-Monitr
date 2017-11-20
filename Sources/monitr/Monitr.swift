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
import SwiftShell
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
    static var version: String = "0.6"

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
                config.logger.info("Finished moving media, but new media has already been added. Running again.")
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
            logger.info("Setting up the conversion queue cron jobs")
            self.cronStart = CronJob(pattern: config.convertCronStart, queue: .global(qos: .background)) {
                self.conversionQueue?.start()
            }
            self.cronEnd = CronJob(pattern: config.convertCronEnd, queue: .global(qos: .background)) {
                self.conversionQueue?.stop = true
            }
            let next = MediaDuration(double: cronStart!.pattern.next(Date())!.date!.timeIntervalSinceNow)
            logger.info("Set up conversion cron job! It will begin in \(next.description)")
        }
    }

    private func checkConversionDependencies() throws {
		self.config.logger.info("Making sure we have the required dependencies for transcoding media...") 

        // Check conversion tool dependencies 
        var dependency = "handbrake"
        let response1 = SwiftShell.run(bash: "which HandBrakeCLI")
        guard response1.succeeded, !response1.stdout.isEmpty else {
            var debugMessage = "Error determining if '\(dependency)' dependency is met.\n\tReturn Code: \(response1.exitcode)"
            if !response1.stdout.isEmpty {
                debugMessage += "\n\tStandard Output: '\(response1.stdout)'"
            }
            if !response1.stderror.isEmpty {
                debugMessage += "\n\tStandard Error: '\(response1.stderror)'"
            }
            self.config.logger.debug(debugMessage)
            throw MonitrError.MissingDependency.handbrake 
        } 

        dependency = "mp4v2"
        let response2 = SwiftShell.run(bash: "which mp4track")
        guard response2.succeeded, !response2.stdout.isEmpty else {
            var debugMessage = "Error determining if '\(dependency)' dependency is met.\n\tReturn Code: \(response2.exitcode)"
            if !response2.stdout.isEmpty {
                debugMessage += "\n\tStandard Output: '\(response2.stdout)'"
            }
            if !response2.stderror.isEmpty {
                debugMessage += "\n\tStandard Error: '\(response2.stderror)'"
            }
            self.config.logger.debug(debugMessage)
            throw MonitrError.MissingDependency.mp4v2 
        } 

        dependency = "ffmpeg"
        let response3 = SwiftShell.run(bash: "which ffmpeg")
        guard response3.succeeded, !response3.stdout.isEmpty else {
            var debugMessage = "Error determining if '\(dependency)' dependency is met.\n\tReturn Code: \(response3.exitcode)"
            if !response3.stdout.isEmpty {
                debugMessage += "\n\tStandard Output: '\(response3.stdout)'"
            }
            if !response3.stderror.isEmpty {
                debugMessage += "\n\tStandard Error: '\(response3.stderror)'"
            }
            self.config.logger.debug(debugMessage)
            throw MonitrError.MissingDependency.ffmpeg 
        } 

        dependency = "mkvtoolnix"
        let response4 = SwiftShell.run(bash: "which mkvpropedit")
        guard response4.succeeded, !response4.stdout.isEmpty else {
            var debugMessage = "Error determining if '\(dependency)' dependency is met.\n\tReturn Code: \(response4.exitcode)"
            if !response4.stdout.isEmpty {
                debugMessage += "\n\tStandard Output: '\(response4.stdout)'"
            }
            if !response4.stderror.isEmpty {
                debugMessage += "\n\tStandard Error: '\(response4.stderror)'"
            }
            self.config.logger.debug(debugMessage)
            throw MonitrError.MissingDependency.mkvtoolnix 
        } 

        dependency = "transcode-video"
        let response5 = SwiftShell.run(bash: "which transcode-video")
        guard response5.succeeded, !response5.stdout.isEmpty else {
            var debugMessage = "Error determining if '\(dependency)' dependency is met.\n\tReturn Code: \(response5.exitcode)"
            if !response5.stdout.isEmpty {
                debugMessage += "\n\tStandard Output: '\(response5.stdout)'"
            }
            if !response5.stderror.isEmpty {
                debugMessage += "\n\tStandard Error: '\(response5.stderror)'"
            }
            self.config.logger.debug(debugMessage)
            throw MonitrError.MissingDependency.transcode_video 
        }
    }

    /// Gets all media object and moves them to Plex then deletes all the empty
    ///   directories left in the downloads directory
    public func run() {
        // Set that we're modifying the media as long as we're still contained in the run function
        self.isModifyingMedia = true
        var failed: [Media] = []
        // Unset the isModifyingMedia as soon as the run function completes
        defer {
            let toClean = self.config.downloadDirectories + self.config.homeVideoDownloadDirectories
            // Removes all empty directories from the download directory
            self.cleanup(dirs: toClean, except: failed.map({ $0.path }) + toClean)
            self.isModifyingMedia = false
        }
        // Get all the media in the downloads directory
        var media = self.getAllMedia(from: self.config.downloadDirectories)
        let homeMedia = self.getAllMedia(from: self.config.homeVideoDownloadDirectories)
        for m in homeMedia where m is Video {
            let media = m as! Video
            media.isHomeMedia = true
            media.subtitles.forEach { s in 
                s.isHomeMedia = true
            }
        }
        media += homeMedia

        guard media.count > 0 else {
            self.config.logger.info("No media found.")
            return
        }

        let video = media.filter { $0 is Video }
        let audio = media.filter { $0 is Audio }
        let ignorable = media.filter { $0 is Ignore }

        self.config.logger.info("Found \(media.count) files in the download directories!")
        if homeMedia.count > 0 {
            self.config.logger.info("\t \(homeMedia.count) home media files")
        }
        if video.count > 0 {
            self.config.logger.info("\t \(video.count) video files")
            self.config.logger.verbose(video.map { $0.path })
        }
        if audio.count > 0 {
            self.config.logger.info("\t \(audio.count) audio files")
            self.config.logger.verbose(audio.map { $0.path })
        }
        if ignorable.count > 0 {
            self.config.logger.info("\t \(ignorable.count) ignorable files")
            self.config.logger.verbose(ignorable.map { $0.path })
        }

        // If we want to convert media, lets do that before we move it to plex
        //   NOTE: If convertImmediately is false, then a queue of conversion 
        //         jobs are created to be run during the scheduled time period
        if self.config.convert, let unconvertedMedia = self.convertMedia(&media) {
            failed += unconvertedMedia as [Media]
            self.config.logger.warning("Failed to convert media:\n\t\(unconvertedMedia.map({ $0.path }))")
        }

        // If we gathered any supported media files, move them to their plex location
        if let unmovedMedia = self.moveMedia(&media) {
            failed += unmovedMedia
            self.config.logger.warning("Failed to move media to plex:\n\t\(unmovedMedia.map({ $0.path }))")
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
        self.config.logger.info("Shutting down monitr.")
        self.config.stopMonitoring()
        self.config.logger.info("Saving the program's statistics")
        try? self.statistics.save(self.config.configFile.parent)
        if (self.conversionQueue?.waiting ?? 0) > 0 {
            self.config.logger.info("Saving conversion queue")
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
                self.config.logger.info("Waiting for current conversion jobs to finish before shutting down")
                self.conversionQueue?.conversionGroup.wait()
            }
        }
    }

    /**
     Gets all the supported Plex media files from the path

     - Parameter from: The path to recursively search through for supported media

     - Returns: An array of the supported media files found
    */
    func getAllMedia(from paths: [Path]) -> [Media] {
        var media: [Media] = []
        for path in paths {
            do {
                // Get all the children in the downloads directory
                let children = try path.recursiveChildren()
                // Iterate of the children paths
                // Skips the directories and just checks for files
                for childFile in children where childFile.isFile {
                    if let m = self.getMedia(with: childFile) {
                        if !(m is Video.Subtitle) {
                            media.append(m)
                        }
                    } else {
                        self.config.logger.warning("Unknown/unsupported file found: \(childFile)")
                    }
                }
            } catch {
                self.config.logger.warning("Failed to get recursive children from the downloads directory.")
                self.config.logger.error(error)
            }
        }
        return media
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
                    let normal = file.normalized.string
                    for base in self.config.downloadDirectories + self.config.homeVideoDownloadDirectories {
                        if normal.range(of: base.string) != nil {
                            video.findSubtitles(below: base, log: self.config.logger)
                            return video
                        }
                    }
                } catch MediaError.VideoError.sampleMedia {
                    return try Ignore(file)
                }
            } else if Audio.isSupported(ext: ext) {
                return try Audio(file)
            } else if Ignore.isSupported(ext: ext) || file.string.lowercased().hasSuffix(".ds_store") {
                return try Ignore(file)
            } else if Video.Subtitle.isSupported(ext: ext) {
                return try Video.Subtitle(file)
            }
        } catch {
            self.config.logger.warning("Error occured trying to create media object from '\(file)'.")
            self.config.logger.error(error)
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
                        m = try m.move(to: self.config.plexDirectory, log: self.config.logger)
                        if self.config.deleteSubtitles && m is Video {
                            m = try (m as! Video).deleteSubtitles() as Media
                        }
                    } catch {
                        self.config.logger.warning("Failed to move media: \(m.path)")
                        self.config.logger.error(error)
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

        self.config.logger.info("Getting the array of media that needs to be converted.")
        let mediaToConvert: [ConvertibleMedia] = media.filter {
            guard $0 is ConvertibleMedia else { return false }
            if $0 is Video {
                do {
                    guard try Video.needsConversion(file: $0.path, with: videoConfig, log: self.config.logger) else { return false }
                } catch {}
                logger.info("We must convert video file '\($0.path.absolute)' for Plex Direct Play/Stream.")
                return true
            } else if  $0 is Audio {
                do {
                    guard try Audio.needsConversion(file: $0.path, with: audioConfig, log: self.config.logger) else { return false }
                } catch {}
                logger.info("We must convert audio file '\($0.path.absolute)' for Plex Direct Play/Stream.")
                return true
            }
            return false
            } as! [ConvertibleMedia]

        if self.config.convertImmediately {
            self.config.logger.verbose("Converting media immediately")

            let convertGroup = AsyncGroup()
            var simultaneousConversions: Int = 0
            for var m in mediaToConvert {
                var config: ConversionConfig?
                if m is Video {
                    config = videoConfig
                } else if m is Audio {
                    config = audioConfig
                }
                simultaneousConversions += 1
                convertGroup.utility {
                    self.statistics.measure(.convert) {
                        do {
                            m = try m.convert(config, self.config.logger)
                        } catch {
                            self.config.logger.warning("Failed to convert file: \(m.path)")
                            self.config.logger.error(error)
                            failedMedia.append(m)
                        }
                    }
                    simultaneousConversions -= 1
                }
                self.config.logger.verbose("Currently running \(simultaneousConversions) simultaneous conversion jobs.")

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
                        self.config.logger.info("Maximum number of conversion threads (\(self.config.convertThreads) threads) reached. Waiting 60 seconds and checking to see if any have finished.")
                        convertGroup.wait(seconds: 60)
                    }
                }
            }
            // Now that we've started all the conversion processes, wait indefinitely for them all to finish
            convertGroup.wait()
        } else {
            if self.conversionQueue == nil {
                self.config.logger.info("Creating a conversion queue")
                self.conversionQueue = ConversionQueue(self.config, statistics: self.statistics)
            } else {
                self.config.logger.info("Using existing conversion queue")
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
    func cleanup(dirs: [Path], except paths: [Path]) {
        for dir in dirs {
            do {
                let children = try dir.children()
                guard children.count > 0 else {
                    guard !paths.contains(dir) else { return }
                    do {
                        try dir.delete()
                    } catch {
                        config.logger.warning("Failed to delete directory '\(dir)'.")
                        config.logger.error(error)
                    }
                    return
                }
                for childDirectory in children where childDirectory.isDirectory {
                    cleanup(dirs: [childDirectory], except: paths)
                }
            } catch {
                config.logger.warning("Failed to get the '\(dir)' directory's children.")
                config.logger.error(error)
            }
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
            config.logger.info("Currently moving media. Will move new media after the current operation is completed.")
            needsUpdate = true
            return
        }
        run()
    }
}
