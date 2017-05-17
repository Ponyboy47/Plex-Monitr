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

enum MonitrError: Error {
    enum MissingDependency: Error {
        case handbrake
        case mp4v2
        case ffmpeg
        case mkvtoolnix
        case transcode_video
    }
    enum CronJob: Error {
        case noNextDate
    }
}

/// Checks the downloads directory for new content to add to Plex
final class Monitr: DirectoryMonitorDelegate {
    /// The current version of monitr
    static var version: String = "0.3.0"

    /// The configuration to use for the monitor
    private var config: Config

    /// The statistics object to track useage data for the monitor
    private var statistics: Statistic = Statistic()

    /// The timer that kicks off the conversionQueue
    private var conversionJob: CronJob?

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

        if self.config.convert {
            try checkConversionDependencies()
        }
    }

    private func checkConversionDependencies() throws {
		struct Output {
        	var stdout: String?
	        var stderr: String?
    	    init (_ out: String?, _ err: String?) {
        	    stdout = out
            	stderr = err
        	}
	    }

		func execute(_ command: String...) -> (Int32, Output) {
            let task = Process()
            task.launchPath = "/usr/bin/env"
            task.arguments = command

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe
            task.launch()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8)
            let stderr = String(data: stderrData, encoding: .utf8)
            task.waitUntilExit()
            return (task.terminationStatus, Output(stdout, stderr))
        }

		self.config.log.info("Making sure we have the required dependencies for transcoding media...") 

        // Check conversion tool dependencies 
        var dependency = "handbrake"
        let (rc1, output1) = execute("which HandBrakeCLI") 
        guard rc1 == 0, let stdout1 = output1.stdout, !stdout1.isEmpty else {
            var errorMessage = "Error determining if '\(dependency)' dependency is met.\nReturn Code: \(rc1)"
            if let stdout = output1.stdout {
                errorMessage += "\nStandard Output: '\(stdout)'"
            }
            if let stderr = output1.stderr {
                errorMessage += "\nStandard Error: '\(stderr)'"
            }
            self.config.log.error(errorMessage)
            throw MonitrError.MissingDependency.handbrake 
        } 

        dependency = "mp4v2"
        let (rc2, output2) = execute("which mp4track") 
        guard rc2 == 0, let stdout2 = output2.stdout, !stdout2.isEmpty else { 
            var errorMessage = "Error determining if '\(dependency)' dependency is met.\nReturn Code: \(rc2)"
            if let stdout = output2.stdout {
                errorMessage += "\nStandard Output: '\(stdout)'"
            }
            if let stderr = output2.stderr {
                errorMessage += "\nStandard Error: '\(stderr)'"
            }
            self.config.log.error(errorMessage)
            throw MonitrError.MissingDependency.mp4v2 
        } 

        dependency = "ffmpeg"
        let (rc3, output3) = execute("which ffmpeg") 
        guard rc3 == 0, let stdout3 = output3.stdout, !stdout3.isEmpty else { 
            throw MonitrError.MissingDependency.ffmpeg 
            var errorMessage = "Error determining if '\(dependency)' dependency is met.\nReturn Code: \(rc3)"
            if let stdout = output3.stdout {
                errorMessage += "\nStandard Output: '\(stdout)'"
            }
            if let stderr = output3.stderr {
                errorMessage += "\nStandard Error: '\(stderr)'"
            }
            self.config.log.error(errorMessage)
        } 

        dependency = "mkvtoolnix"
        let (rc4, output4) = execute("which mkvpropedit") 
        guard rc4 == 0, let stdout4 = output4.stdout, !stdout4.isEmpty else { 
            throw MonitrError.MissingDependency.mkvtoolnix 
            var errorMessage = "Error determining if '\(dependency)' dependency is met.\nReturn Code: \(rc4)"
            if let stdout = output4.stdout {
                errorMessage += "\nStandard Output: '\(stdout)'"
            }
            if let stderr = output4.stderr {
                errorMessage += "\nStandard Error: '\(stderr)'"
            }
            self.config.log.error(errorMessage)
        } 

        dependency = "transcode_video"
        let (rc5, output5) = execute("which transcode_video") 
        guard rc5 == 0, let stdout5 = output5.stdout, !stdout5.isEmpty else { 
            throw MonitrError.MissingDependency.transcode_video 
            var errorMessage = "Error determining if '\(dependency)' dependency is met.\nReturn Code: \(rc5)"
            if let stdout = output5.stdout {
                errorMessage += "\nStandard Output: '\(stdout)'"
            }
            if let stderr = output5.stderr {
                errorMessage += "\nStandard Error: '\(stderr)'"
            }
            self.config.log.error(errorMessage)
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
        let subtitle = media.filter { $0 is Subtitle }
        let audio = media.filter { $0 is Audio }
        let other = media.filter { $0 is Ignore }

        self.config.log.info("Found \(media.count) files in the download directory!")
        if video.count > 0 {
            self.config.log.info("\t \(video.count) video files")
            self.config.log.verbose(video.map { $0.path })
        }
        if subtitle.count > 0 {
            self.config.log.info("\t \(subtitle.count) subtitle files")
            self.config.log.verbose(subtitle.map { $0.path })
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
            self.config.log.warning("Failed to convert media:\n\t\(unconvertedMedia)")
        }

        // If we gathered any supported media files, move them to their plex location
        if let unmovedMedia = self.moveMedia(&media) {
            self.config.log.warning("Failed to move media to plex:\n\t\(unmovedMedia)")
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
        // Go through conversions and halt them/save them
        if now {
            // Kill any other stuff going on
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
        var m: Media?
		let ext = file.extension ?? ""
        do {
            if Video.isSupported(ext: ext) {
                do {
                    m = try Video(file)
                } catch MediaError.sampleMedia {
                    m = try Ignore(file)
                }
            } else if Audio.isSupported(ext: ext) {
                m = try Audio(file)
            } else if Subtitle.isSupported(ext: ext) {
                m = try Subtitle(file)
            } else if Ignore.isSupported(ext: ext) || file.string.lowercased().ends(with: ".ds_store") {
                m = try Ignore(file)
            }
        } catch {
            self.config.log.warning("Error occured trying to create media object from '\(file)'.")
            self.config.log.error(error)
        }
        return m
    }

    /**
     Moves the array of Media objects to their proper locations in the Plex Library

     - Parameter media: The array of Media objects to move

     - Returns: An array of Media objects that failed to move
    */
    func moveMedia(_ media: inout [Media]) -> [Media]? {
        var failedMedia: [Media] = []

        let moveGroup = AsyncGroup()
        for var m in media {
            // Starts a new utility thread to move the file
            moveGroup.utility {
                self.statistics.measure(.move) {
                    do {
                        m = try m.move(to: self.config.plexDirectory, log: self.config.log)
                    } catch {
                        self.config.log.warning("Failed to move media: \(m)")
                        self.config.log.error(error)
                        failedMedia.append(m)
                    }
                }
            }
        }
        // Blocks until all the moveGroup threads have completed
        moveGroup.wait()

        guard failedMedia.count > 0 else { return nil }

        return failedMedia
    }

    /**
     Converts the array of Media object to convert to Plex DirectPlay supported formats

     - Parameter media: The array of Media objects to convert

     - Returns: An array of Media objects that failed to be converted
    */
    func convertMedia(_ media: inout [Media]) -> [Media]? {
        var failedMedia: [Media] = []

        if self.config.convertImmediately {
            self.config.log.verbose("Converting media immediately")
            let videoConfig = VideoConversionConfig(container: self.config.convertVideoContainer, videoCodec: self.config.convertVideoCodec, audioCodec: self.config.convertAudioCodec, subtitleScan: self.config.convertVideoSubtitleScan, mainLanguage: self.config.convertLanguage, maxFramerate: self.config.convertVideoMaxFramerate, plexDir: self.config.plexDirectory, tempDir: self.config.deleteOriginal ? nil : self.config.convertTempDirectory)
            let audioConfig = AudioConversionConfig(container: self.config.convertAudioContainer, codec: self.config.convertAudioCodec, plexDir: self.config.plexDirectory, tempDir: self.config.deleteOriginal ? nil : self.config.convertTempDirectory)

            let convertGroup = AsyncGroup()
            var simultaneousConversions: Int = 0
            for var m in media {
                convertGroup.utility {
                    simultaneousConversions += 1
                    self.statistics.measure(.convert) {
                        do {
                            if m is Video {
                                m = try m.convert(videoConfig, self.config.log)
                            } else if m is Audio {
                                m = try m.convert(audioConfig, self.config.log)
                            } else {
                                m = try m.convert(nil, self.config.log)
                            }
                        } catch {
                            self.config.log.warning("Failed to convert media: \(m)")
                            self.config.log.error(error)
                            failedMedia.append(m)
                        }
                    }
                    simultaneousConversions -= 1
                }
                // Blocks for as long as there are as many conversion jobs
                // running as the configured conversion thread limit
                //   NOTE: Does this by waiting for 60 seconds (or until all
                //   threads have completed) and then rechecking the number of
                //   simultaneous conversions (since the number should
                //   increment when a thread starts and decrement when it
                //   finishes)
                while simultaneousConversions == self.config.convertThreads {
                    convertGroup.wait(seconds: 60)
                }
            }
            // Now that we've started all the conversion processes, wait indefinitely for them all to finish
            convertGroup.wait()
        } else {
            if self.config.conversionQueue == nil {
                self.config.log.info("Creating a conversion queue")
                self.config.conversionQueue = ConversionQueue(self.config, statistics: self.statistics)
            } else {
                self.config.log.info("Using existing conversion queue")
            }

            // Create a queue of conversion jobs for later
            for m in media {
                if m is Video {
                    self.config.conversionQueue!.push(m as! Video)
                } else if m is Audio {
                    self.config.conversionQueue!.push(m as! Audio)
                }
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
