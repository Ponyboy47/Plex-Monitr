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

enum MonitrError: Swift.Error {
}

/// Checks the downloads directory for new content to add to Plex
final class Monitr: DirectoryMonitorDelegate {
    /// The configuration to use for the monitor
    private var config: Config

    /// The statistics object to track useage data for the monitor
    private var statistics: Statistic = Statistic()

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
    }

    /// Gets all media object and moves them to Plex then deletes all the empty
    ///   directories left in the downloads directory
    public func run() {
        Async.background {
            // Set that we're modifying the media as long as we're still contained in the run function
            self.isModifyingMedia = true
            // Unset the isModifyingMedia as soon as the run function completes
            defer {
                // Removes all empty directories from the download directory
                self.cleanup(dir: self.config.downloadDirectory)
                self.isModifyingMedia = false
            }
            // Get all the media in the downloads directory
            let media = self.getAllMedia(from: self.config.downloadDirectory)

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
            if self.config.convert, let unconvertedMedia = self.convertMedia(media) {
                self.config.log.warning("Failed to convert media:\n\t\(unconvertedMedia)")
            }

            // If we gathered any supported media files, move them to their plex location
            if let unmovedMedia = self.moveMedia(media) {
                self.config.log.warning("Failed to move media to plex:\n\t\(unmovedMedia)")
            }
        }
    }

    /// Sets the delegate for the downloads directory monitor
    public func setDelegate() {
        config.setDelegate(self)
    }

    /// Begin watching the downloads directory
    @discardableResult
    public func startMonitoring() -> Bool {
        return config.startMonitoring()
    }

    /**
     Stop watching the downloads directory

     - Parameter now: If true, kills any active media management. Defaults to false
    */
    public func shutdown(now: Bool = false) {
        config.log.info("Shutting down monitr.")
        config.stopMonitoring()
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
                if let m = getMedia(with: childFile) {
                    media.append(m)
                } else {
                    config.log.warning("Unknown/unsupported file found: \(childFile)")
                }
            }
            return media
        } catch {
            config.log.warning("Failed to get recursive children from the downloads directory.")
            config.log.error(error)
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
            config.log.warning("Error occured trying to create media object from '\(file)'.")
            config.log.error(error)
        }
        return m
    }

    /**
     Moves the array of Media objects to their proper locations in the Plex Library

     - Parameter media: The array of Media objects to move

     - Returns: An array of Media objects that failed to move
    */
    func moveMedia(_ media: [Media]) -> [Media]? {
        var failedMedia: [Media] = []

        for m in media {
            do {
                try m.move(to: config.plexDirectory, log: config.log)
            } catch {
                config.log.warning("Failed to move media: \(m)")
                config.log.error(error)
                failedMedia.append(m)
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
    func convertMedia(_ media: [Media]) -> [Media]? {
        var failedMedia: [Media] = []

        if config.convertImmediately {
            config.log.verbose("Converting media immediately")
            for m in media {
                do {
                    try m.convert(config.log)
                } catch {
                    config.log.warning("Failed to convert media: \(m)")
                    config.log.error(error)
                    failedMedia.append(m)
                }
            }
        } else {
            if config.conversionQueue == nil {
                config.log.info("Creating a conversion queue")
                config.conversionQueue = ConversionQueue(config, statistics: statistics)
            } else {
                config.log.info("Using existing conversion queue")
            }

            // Create a queue of conversion jobs for later
            for m in media {
                if Video.isSupported(ext: m.path.`extension` ?? "") && Video.needsConversion(file: m.path) {
                    config.conversionQueue?.push(m as! Video)
                } else if Audio.isSupported(ext: m.path.`extension` ?? "") && Audio.needsConversion(file: m.path) {
                    config.conversionQueue?.push(m as! Audio)
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
