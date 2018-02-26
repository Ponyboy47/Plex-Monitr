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
import SwiftyBeaver
import Dispatch

enum MonitrError: Error {
    case missingDependency(Dependency)
    case missingDependencies([Dependency])
}
enum Dependency: String {
    case handbrake = "HandBrakeCLI"
    case mp4v2 = "mp4track"
    case ffmpeg
    case mkvtoolnix = "mkvpropedit"
    case transcode_video = "transcode-video"

    static let all: [Dependency] = [.handbrake, .mp4v2, .ffmpeg, .mkvtoolnix, .transcode_video]
}

/// Checks the downloads directory for new content to add to Plex
final class Monitr<M> where M: Media & Equatable {
    /// The current version of monitr
    static var version: String { return "0.7.0" }

    /// The configuration to use for the monitor
    private var config: Config

    /// The queue of objects needing to be converted
    private var conversionQueue: AutoAsyncQueue<M, MediaState>?
    private var cronStart: CronJob?
    private var cronEnd: CronJob?
    private lazy var conversionQueueFilename: String = { return "conversionqueue.\(M.self).json" }()

    /// Whether or not media is currently being migrated to Plex. Automatically
    ///   runs a new again if new media has been added since the run routine began
    var isModifyingMedia: Bool = false {
        didSet {
            if !isModifyingMedia && needsUpdate {
                config.logger.info("Finished moving \(M.self) media, but new \(M.self) media has already been added. Running again.")
                needsUpdate = false
                run()
            }
        }
    }
    /// If new content has been added since the run routine began
    var needsUpdate: Bool = false

    init(logger: SwiftyBeaver.Type) {
        config = Config(logger)
    }

    init(_ config: Config) throws {
        self.config = config

        // Since this media is not convertible, let's just set this false and not deal with it
        self.config.convert = false
    }

    /// Gets all media object and moves them to Plex then deletes all the empty
    ///   directories left in the downloads directory
    public func run() {
        // Set that we're modifying the media as long as we're still contained in the run function
        isModifyingMedia = true

        // Unset the isModifyingMedia as soon as the run function completes
        defer {
            isModifyingMedia = false
        }
        // Get all the media in the downloads directory
        var media = getAllMedia(from: config.downloadDirectories)
        let homeMedia = getAllMedia(from: config.homeVideoDownloadDirectories)
        for m in homeMedia where m is Video {
            let media = m as! Video
            media.isHomeMedia = true
            media.subtitles.forEach { subtitle in
                subtitle.isHomeMedia = true
            }
        }
        media += homeMedia

        guard media.count > 0 else {
            config.logger.info("No \(M.self) media found.")
            return
        }

        config.logger.info("Found \(media.count) \(M.self) files in the download directories!")
        config.logger.verbose(media.map { $0.path })

        if media is [ConvertibleMedia] && config.convert {
            setupConversionQueue(media as! [ConvertibleMedia])
        }

        for m in media {
            do {
                let state: MediaState
                if m is ConvertibleMedia {
                    state = try (m as! ConvertibleMedia).move(to: config.plexDirectory, logger: config.logger)
                } else {
                    state = try m.move(to: config.plexDirectory, logger: config.logger)
                }

                switch state {
                // .subtitle only should occur when moving the subtitle file failed
                case .subtitle(_, let s):
                    config.logger.warning("Failed to move subtitle '\(s.path)' to plex")
                // .unconverted files can only be moved. So it will never be anything besides .failed(.moving, _)
                case .unconverted(let s):
                    switch s {
                    case .failed(_, let u):
                        config.logger.warning("Failed to move unconverted \(M.self) media '\(u.path)' to plex")
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
                        config.logger.error("Failed to move \(M.self) media: \(f.path)")
                    case .converting:
                        config.logger.error("Failed to convert \(M.self) media: \(f.path)")
                    case .deleting:
                        config.logger.error("Failed to delete \(M.self) media: \(f.path)")
                    default: continue
                    }
                default: continue
                }

                if config.deleteSubtitles && m is Video {
                    try (m as! Video).deleteSubtitles()
                }
            } catch {
                config.logger.warning("Failed to move/convert \(M.self) media: \(m.path)")
                config.logger.error(error)
            }
        }
    }

    private func setupConversionQueue(_ media: [ConvertibleMedia]) {
        let videoConfig = VideoConversionConfig(config: config)
        let audioConfig = AudioConversionConfig(config: config)
        media.forEach({ media in
            if media is Video {
                (media as! Video).conversionConfig = videoConfig
            } else if media is Audio {
                (media as! Audio).conversionConfig = audioConfig
            }
        })

        if conversionQueue == nil {
            conversionQueue = AutoAsyncQueue<M, MediaState>(maxSimultaneous: config.convertThreads, logger: config.logger) { convertibleMedia in
                do {
                    let state = try (convertibleMedia as! ConvertibleMedia).convert(self.config.logger)
                    switch state {
                    case .success:
                        self.config.logger.info("Finished converting media! Moving now")
                        return try (convertibleMedia as! ConvertibleMedia).move(to: self.config.plexDirectory, logger: self.config.logger)
                    default:
                        self.config.logger.info("Failed converting media! \(state)")
                        return state
                    }
                } catch {
                    self.config.logger.error("Error while converting \(M.self) media: \(error)")
                    return .failed(.converting, convertibleMedia)
                }
            }
        }

        if config.convertImmediately {
            conversionQueue?.start()
        }
    }

    /**
     Stop watching the downloads directory

     - Parameter now: If true, kills any active media management. Defaults to false
    */
    public func shutdown(now: Bool = false) {
        config.logger.info("Shutting down \(M.self) monitr.")
        conversionQueue?.stop()
        if (conversionQueue?.queue.count ?? 0) > 0 {
            config.logger.info("Saving \(M.self) conversion queue")
            try? conversionQueue?.save(to: config.configFile.parent + conversionQueueFilename)
        }
        // Go through conversions and halt them/save them
        if now {
            // Kill any other stuff going on
            if (conversionQueue?.active.count ?? 0) > 0 {
                // TODO: Kill and cleanup current conversion jobs
            }
        } else {
            if (conversionQueue?.active.count ?? 0) > 0 {
                config.logger.info("Waiting for current \(M.self) conversion jobs to finish before shutting down")
                conversionQueue?.wait()
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
                let children = try path.children()

                let group = DispatchGroup()
                let queue = DispatchQueue(label: "com.monitr.\(M.self).\(Foundation.UUID().description).getAllMedia", qos: .userInitiated)
                let childDirs = children.filter { $0.isDirectory }
                queue.async(group: group) {
                    media.append(contentsOf: self.getAllMedia(from: childDirs))
                }

                // Iterate of the children paths
                // Skips the directories and just checks for files
                for childFile in children where childFile.isFile {
                    queue.async(group: group) {
                        if let m = self.getMedia(with: childFile) {
                            if !(m is Video.Subtitle) && m is M {
                                media.append(m)
                            }
                        } else {
                            self.config.logger.warning("Unknown/unsupported file found: \(childFile)")
                        }
                    }
                }
                group.wait()
            } catch {
                config.logger.warning("Failed to get \(M.self) children from the downloads directory.")
                config.logger.error(error)
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
                    for base in config.downloadDirectories + config.homeVideoDownloadDirectories {
                        if normal.range(of: base.string) != nil {
                            video.findSubtitles(below: base, logger: config.logger)
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
            config.logger.warning("Error occured trying to create media object from '\(file)'.")
            config.logger.error(error)
        }
        return nil
    }
}

extension Monitr where M: ConvertibleMedia {
    convenience init(_ config: Config) throws {
        self.init(logger: config.logger)

        self.config = config

        if config.convert {
            try checkConversionDependencies()
        }

        let conversionQueueFile = config.configFile.parent + conversionQueueFilename
        if conversionQueueFile.exists && conversionQueueFile.isFile {
            conversionQueue = try AutoAsyncQueue<M, MediaState>(fromFile: conversionQueueFile, with: logger) { convertibleMedia in
                do {
                    let state = try convertibleMedia.convert(self.config.logger)
                    switch state {
                    case .success:
                        return try (convertibleMedia as! ConvertibleMedia).move(to: self.config.plexDirectory, logger: self.config.logger)
                    default: return state
                    }
                } catch {
                    self.config.logger.error("Error while converting \(M.self) media: \(error)")
                    return .failed(.converting, convertibleMedia)
                }
            }
        }

        if config.convert && !config.convertImmediately {
            logger.info("Setting up the \(M.self) conversion queue cron jobs")
            cronStart = CronJob(pattern: config.convertCronStart, queue: .global(qos: .background)) {
                self.conversionQueue?.start()
            }
            cronEnd = CronJob(pattern: config.convertCronEnd, queue: .global(qos: .background)) {
                self.conversionQueue?.stop()
            }
            let next = MediaDuration(double: cronStart!.pattern.next(Date())!.date!.timeIntervalSinceNow)
            logger.info("Set up \(M.self) conversion cron job! It will begin in \(next.description)")
        }
    }

    private func checkConversionDependencies() throws {
        config.logger.info("Making sure we have the required dependencies for transcoding \(M.self) media...")

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.monitr.dependencies", qos: .userInteractive)

        var missing: [Dependency] = []

        for dependency in Dependency.all {
            queue.async(group: group) {
                let response = SwiftShell.run(bash: "which \(dependency.rawValue)")
                if !response.succeeded || response.stdout.isEmpty {
                    var debugMessage = "Error determining if '\(missing)' dependency is met.\n\tReturn Code: \(response.exitcode)"
                    if !response.stdout.isEmpty {
                        debugMessage += "\n\tStandard Output: '\(response.stdout)'"
                    }
                    if !response.stderror.isEmpty {
                        debugMessage += "\n\tStandard Error: '\(response.stderror)'"
                    }
                    self.config.logger.debug(debugMessage)
                    missing.append(dependency)
                }
            }
        }

        group.wait()

        guard missing.isEmpty else {
            if missing.count == 1 {
                throw MonitrError.missingDependency(missing.first!)
            } else {
                throw MonitrError.missingDependencies(missing)
            }
        }
    }
}
