/*

    Monitr.swift

    Created By: Jacob Williams
    Description: This file contains the Monitr class, which is used to continually check the 
                   downloads directory for new content and distribute it appropriately.
    License: MIT License

*/

import Foundation
import PathKit
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
final class Monitr<M>: DirectoryMonitorDelegate where M: Media & Equatable {
    /// The current version of monitr
    static var version: String { return "0.7.0" }

    /// The configuration to use for the monitor
    private var config: Config

    /// The queue of objects needing to be converted
    private var conversionQueue: AutoAsyncQueue<M>?
    private var cronStart: CronJob?
    private var cronEnd: CronJob?
    private lazy var conversionQueueFilename: String = { return "conversionqueue.\(M.self).json" }()

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

        // Since this media is not convertible, let's just set this false and not deal with it
        self.config.convert = false
    }

    /// Gets all media object and moves them to Plex then deletes all the empty
    ///   directories left in the downloads directory
    public func run() {
        // Set that we're modifying the media as long as we're still contained in the run function
        self.isModifyingMedia = true

        // Unset the isModifyingMedia as soon as the run function completes
        defer {
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

        if self.config.convert {
                let videoConfig = VideoConversionConfig(container: self.config.convertVideoContainer, videoCodec: self.config.convertVideoCodec, audioCodec: self.config.convertAudioCodec, subtitleScan: self.config.convertVideoSubtitleScan, mainLanguage: self.config.convertLanguage, maxFramerate: self.config.convertVideoMaxFramerate, plexDir: self.config.plexDirectory, tempDir: self.config.deleteOriginal ? nil : self.config.convertTempDirectory)
                let audioConfig = AudioConversionConfig(container: self.config.convertAudioContainer, codec: self.config.convertAudioCodec, plexDir: self.config.plexDirectory, tempDir: self.config.deleteOriginal ? nil : self.config.convertTempDirectory)
                media.forEach({ m in
                    if m is Video {
                        (m as! Video).conversionConfig = videoConfig
                    } else if m is Audio {
                        (m as! Audio).conversionConfig = audioConfig
                    }
                })

            if self.conversionQueue == nil {
                self.conversionQueue = AutoAsyncQueue<M>(maxSimultaneous: self.config.convertThreads, logger: self.config.logger) { convertibleMedia in
                    do {
                        let state = try (convertibleMedia as! ConvertibleMedia).convert(self.config.logger)
                        switch state {
                        default: return
                        }
                    } catch {
                        print("Error while converting media: \(error)")
                    }
                }
            }

            self.conversionQueue?.start()
        }
        
        for m in media {
            do {
                let state: MediaState
                if m is ConvertibleMedia {
                    state = try (m as! ConvertibleMedia).move(to: self.config.plexDirectory, logger: self.config.logger)
                } else {
                    state = try m.move(to: self.config.plexDirectory, logger: self.config.logger)
                }

                switch state {
                // .subtitle only should occur when moving the subtitle file failed
                case .subtitle(_, let s):
                    self.config.logger.warning("Failed to move subtitle '\(s.path)' to plex")
                // .unconverted files can only be moved. So it will never be anything besides .failed(.moving, _)
                case .unconverted(let s):
                    switch s {
                    case .failed(_, let u):
                        self.config.logger.warning("Failed to move unconverted media '\(u.path)' to plex")
                    default: continue
                    }
                // .waiting should only occur when there is media waiting to be converted
                case .waiting(let s):
                    switch s {
                    case .converting:
                        conversionQueue?.append(m as! M)
                    default: continue
                    }
                case .failed(let s, let f):
                    switch s {
                    case .moving:
                        self.config.logger.error("Failed to move media: \(f.path)")
                    case .converting:
                        self.config.logger.error("Failed to convert media: \(f.path)")
                    case .deleting:
                        self.config.logger.error("Failed to delete media: \(f.path)")
                    default: continue
                    }
                default: continue
                }

                if self.config.deleteSubtitles && m is Video {
                    try (m as! Video).deleteSubtitles()
                }
            } catch {
                self.config.logger.warning("Failed to move/convert media: \(m.path)")
                self.config.logger.error(error)
            }
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
        self.conversionQueue?.stop()
        if (self.conversionQueue?.queue.count ?? 0) > 0 {
            self.config.logger.info("Saving conversion queue")
            try? self.conversionQueue?.save(to: config.configFile.parent + self.conversionQueueFilename)
        }
        // Go through conversions and halt them/save them
        if now {
            // Kill any other stuff going on
            if (self.conversionQueue?.active.count ?? 0) > 0 {
                // TODO: Kill and cleanup current conversion jobs
            }
        } else {
            if (self.conversionQueue?.active.count ?? 0) > 0 {
                self.config.logger.info("Waiting for current conversion jobs to finish before shutting down")
                self.conversionQueue?.wait()
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
                            video.findSubtitles(below: base, logger: self.config.logger)
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

extension Monitr where M: ConvertibleMedia {
    convenience init(_ config: Config) throws {
        try self.init(config)

        // Overwrite the main initializer and set convert to it's true value
        self.config.convert = config.convert

        if config.convert {
            try checkConversionDependencies()
        }

        let conversionQueueFile = config.configFile.parent + self.conversionQueueFilename
        if conversionQueueFile.exists && conversionQueueFile.isFile {
            self.conversionQueue = try AutoAsyncQueue<M>(fromFile: conversionQueueFile, with: config.logger) { convertibleMedia in
                do {
                    let state = try convertibleMedia.convert(self.config.logger)
                    switch state {
                    default: return
                    }
                } catch {
                    print("Error while converting media: \(error)")
                }
            }
        }

        if config.convert && !config.convertImmediately {
            logger.info("Setting up the conversion queue cron jobs")
            self.cronStart = CronJob(pattern: config.convertCronStart, queue: .global(qos: .background)) {
                self.conversionQueue?.start()
            }
            self.cronEnd = CronJob(pattern: config.convertCronEnd, queue: .global(qos: .background)) {
                self.conversionQueue?.stop()
            }
            let next = MediaDuration(double: cronStart!.pattern.next(Date())!.date!.timeIntervalSinceNow)
            logger.info("Set up conversion cron job! It will begin in \(next.description)")
        }
    }

    private func checkConversionDependencies() throws {
        self.config.logger.info("Making sure we have the required dependencies for transcoding media...")

        // Check conversion tool dependencies
        let response1 = SwiftShell.run(bash: "which HandBrakeCLI")
        guard response1.succeeded, !response1.stdout.isEmpty else {
            var debugMessage = "Error determining if 'handbrake' dependency is met.\n\tReturn Code: \(response1.exitcode)"
            if !response1.stdout.isEmpty {
                debugMessage += "\n\tStandard Output: '\(response1.stdout)'"
            }
            if !response1.stderror.isEmpty {
                debugMessage += "\n\tStandard Error: '\(response1.stderror)'"
            }
            self.config.logger.debug(debugMessage)
            throw MonitrError.MissingDependency.handbrake
        }

        let response2 = SwiftShell.run(bash: "which mp4track")
        guard response2.succeeded, !response2.stdout.isEmpty else {
            var debugMessage = "Error determining if 'mp4v2' dependency is met.\n\tReturn Code: \(response2.exitcode)"
            if !response2.stdout.isEmpty {
                debugMessage += "\n\tStandard Output: '\(response2.stdout)'"
            }
            if !response2.stderror.isEmpty {
                debugMessage += "\n\tStandard Error: '\(response2.stderror)'"
            }
            self.config.logger.debug(debugMessage)
            throw MonitrError.MissingDependency.mp4v2
        }

        let response3 = SwiftShell.run(bash: "which ffmpeg")
        guard response3.succeeded, !response3.stdout.isEmpty else {
            var debugMessage = "Error determining if 'ffmpeg' dependency is met.\n\tReturn Code: \(response3.exitcode)"
            if !response3.stdout.isEmpty {
                debugMessage += "\n\tStandard Output: '\(response3.stdout)'"
            }
            if !response3.stderror.isEmpty {
                debugMessage += "\n\tStandard Error: '\(response3.stderror)'"
            }
            self.config.logger.debug(debugMessage)
            throw MonitrError.MissingDependency.ffmpeg
        }

        let response4 = SwiftShell.run(bash: "which mkvpropedit")
        guard response4.succeeded, !response4.stdout.isEmpty else {
            var debugMessage = "Error determining if 'mkvtoolnix' dependency is met.\n\tReturn Code: \(response4.exitcode)"
            if !response4.stdout.isEmpty {
                debugMessage += "\n\tStandard Output: '\(response4.stdout)'"
            }
            if !response4.stderror.isEmpty {
                debugMessage += "\n\tStandard Error: '\(response4.stderror)'"
            }
            self.config.logger.debug(debugMessage)
            throw MonitrError.MissingDependency.mkvtoolnix
        }

        let response5 = SwiftShell.run(bash: "which transcode-video")
        guard response5.succeeded, !response5.stdout.isEmpty else {
            var debugMessage = "Error determining if 'transcode-video' dependency is met.\n\tReturn Code: \(response5.exitcode)"
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
}
