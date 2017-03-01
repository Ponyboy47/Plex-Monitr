/*

    Monitr.swift

    Created By: Jacob Williams
    Description: This file contains the Monitr class, which is used to continually check the 
                   downloads directory for new content and distribute it appropriately.
    License: MIT License

*/

import Foundation
import PathKit
//import Async

enum MonitrError: Swift.Error {
}

/// Checks the downloads directory for new content to add to Plex
class Monitr: DirectoryMonitorDelegate {
    /// The configuration to use for the monitor
    private var config: Config
    /// Whether or not media is currently being migrated to Plex. Automatically
    ///   runs a new again if new media has been added since the run routine began
    private var isModifyingMedia: Bool = false {
        didSet {
            if !isModifyingMedia && needsUpdate {
                needsUpdate = false
                run()
            }
        }
    }
    /// If new content has been added since the run routine began
    private var needsUpdate: Bool = false

    init(_ config: Config) {
        self.config = config
    }

    /// Gets all media object and moves them to Plex then deletes all the empty
    ///   directories left in the downloads directory
    public func run() {
        //Async.background {
            // Set that we're modifying the media as long as we're still contained in the run function
            self.isModifyingMedia = true
            // Unset the isModifyingMedia as soon as the run function completes
            defer {
                self.isModifyingMedia = false
            }
            // Get all the media in the downloads directory
            let media = self.getAllMedia(from: self.config.downloadDirectory)
            // If we gathered any supported media files, move them to their plex location
            if media.count > 0, let unmovedMedia = self.moveMedia(media) {
                print("Failed to move media to plex:\n\t\(unmovedMedia)")
            }
            // Removes all empty directories from the download directory
            self.cleanup(dir: self.config.downloadDirectory)
        //}
    }

    /// Sets the delegate for the downloads directory monitor
    public func setDelegate() {
        config.setDelegate(self)
    }

    /// Begin watching the downloads directory
    public func startMonitoring() {
        config.startMonitoring()
    }

    /**
     Stop watching the downloads directory

     - Parameter now: If true, kills any active media management. Defaults to false
    */
    public func shutdown(now: Bool = false) {
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
                    print("Unknown/unsupported file found: \(childFile)")
                }
            }
            return media
        } catch {
            print("Failed to get recursive children from the downloads directory.\n\t\(error)")
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
                m = try Video(file)
            } else if Audio.isSupported(ext: ext) {
                m = try Audio(file)
            } else if Subtitle.isSupported(ext: ext) {
                m = try Subtitle(file)
            } else if Ignore.isSupported(ext: ext) {
                m = try Ignore(file)
            }
        } catch {
            print("Error occured trying to get media.\n\t\(error)")
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

        for var m in media {
            do {
                try m.move(to: config.plexDirectory)
            } catch {
                print("Failed to move media: \(m)\n\t\(error)")
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
        
        for var m in media {
            do {
                try m.convert()
            } catch {
                print("Failed to convert media: \(m)\n\t\(error)")
                failedMedia.append(m)
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
                do {
                    try dir.delete()
                } catch {
                    print("Failed to delete directory.\n\t\(error)")
                }
                return
            }
            for childDirectory in children where childDirectory.isDirectory {
                cleanup(dir: childDirectory)
            }
        } catch {
            print("Failed to get the directory's children.\n\t\(error)")
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
            needsUpdate = true
            return
        }
        run()
    }
}
