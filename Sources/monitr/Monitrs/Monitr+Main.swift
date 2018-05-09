import Dispatch
import PathKit
import Cron

final class MainMonitr: DirectoryMonitorDelegate {
    /// The current version of monitr
    static var version: String { return "0.7.0" }

    let videoMonitr: ConvertibleMonitr<Video>
    let audioMonitr: ConvertibleMonitr<Audio>
    let ignoreMonitr: Monitr<Ignore>

    let config: Config

    let queue: DispatchQueue = DispatchQueue(label: "MainMonitrQueue", qos: .userInitiated, attributes: .concurrent)
    let moveOperationQueue: MediaOperationQueue
    let convertOperationQueue: MediaOperationQueue

    var cronStart: CronJob!
    var cronEnd: CronJob!

    var currentMedia: [Media] = []

    var isRunning: Bool = false {
        didSet {
            // If we went from running to not running and needsUpdate is true, then we should run again just in case
            if oldValue && !isRunning && needsUpdate {
                needsUpdate = false
                self.run()
            }
        }
    }
    var needsUpdate: Bool = false

    init(config: Config) throws {
        let moveOperationQueueFile = config.configFile.parent + "moveOperationQueue.json"
        if moveOperationQueueFile.exists && moveOperationQueueFile.isFile {
            moveOperationQueue = try MediaOperationQueue(from: moveOperationQueueFile)
        } else {
            moveOperationQueue = MediaOperationQueue(1)
        }

        let convertOperationQueueFile = config.configFile.parent + "convertOperationQueue.json"
        if convertOperationQueueFile.exists && convertOperationQueueFile.isFile {
            convertOperationQueue = try MediaOperationQueue(from: convertOperationQueueFile)
        } else {
            convertOperationQueue = MediaOperationQueue(config.convertThreads)
        }

        self.config = config

        videoMonitr = try ConvertibleMonitr<Video>(config, moveOperationQueue: moveOperationQueue, convertOperationQueue: convertOperationQueue)
        audioMonitr = try ConvertibleMonitr<Audio>(config, moveOperationQueue: moveOperationQueue, convertOperationQueue: convertOperationQueue)
        ignoreMonitr = try Monitr<Ignore>(config, moveOperationQueue: moveOperationQueue)

        if config.convert && !config.convertImmediately {
            convertOperationQueue.isSuspended = true
            logger.verbose("Setting up the conversion queue cron jobs")
            cronStart = CronJob(pattern: config.convertCronStart, queue: .global(qos: .background)) {
                self.convertOperationQueue.isSuspended = false
            }
            cronEnd = CronJob(pattern: config.convertCronEnd, queue: .global(qos: .background)) {
                self.convertOperationQueue.isSuspended = true
            }
            let next = MediaDuration(double: cronStart!.pattern.next(Date())!.date!.timeIntervalSinceNow)
            logger.verbose("Set up the conversion cron jobs! It will begin in \(next.description)")
        }
    }

    private func setHomeMedia(_ homeMedia: [Media]) {
        homeMedia.forEach { media in
            media.isHomeMedia = true
            if media is Video {
                (media as! Video).subtitles.forEach { $0.isHomeMedia = true }
            }
        }
    }

    func run() {
        isRunning = true

        defer { isRunning = false }

        var media = getAllMedia(from: config.downloadDirectories)
        let homeMedia = getAllMedia(from: config.homeVideoDownloadDirectories)

        // Get all the media in the downloads directory
        setHomeMedia(homeMedia)
        media += homeMedia

        config.logger.debug("Found \(media.count) total media files in the downloads directories")

        // Remove items that we're currently processing
        // swiftlint:disable identifier_name
        media = media.filter { m in
            !currentMedia.contains(where: { c in
                return m.plexFilename == c.plexFilename
            })
        }
        // swiftlint:enable identifier_name

        // If there's no new media, don't continue
        guard !media.isEmpty else { return }

        currentMedia += media

        config.logger.info("Found \(media.count) new media files to process")

        let videoMedia = media.filter { $0 is Video }.map { $0 as! Video }
        let audioMedia = media.filter { $0 is Audio }.map { $0 as! Audio }
        let ignoredMedia = media.filter { $0 is Ignore }.map { $0 as! Ignore }

        queue.async {
            self.videoMonitr.run(videoMedia)
        }

        queue.async {
            self.audioMonitr.run(audioMedia)
        }

        queue.async {
            self.ignoreMonitr.run(ignoredMedia)
        }
    }

    func setDelegate() {
        self.config.setDelegate(self)
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
                // swiftlint:disable identifier_name
                for childFile in children where childFile.isFile {
                    if let m = self.getMedia(with: childFile) {
                        m.mainMonitr = self
                        if !(m is Video.Subtitle) {
                            media.append(m)
                        }
                    } else {
                        self.config.logger.warning("Unknown/unsupported file found: \(childFile)")
                    }
                }
                // swiftlint:enable identifier_name
            } catch {
                config.logger.error("Failed to get files from the downloads directories.")
                config.logger.debug(error)
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
            config.logger.error("Error occured trying to create media object from '\(file)'.")
            config.logger.debug(error)
        }
        return nil
    }

    @discardableResult
    func startMonitoring() -> Bool {
        return self.config.startMonitoring()
    }

    /**
     Stop watching the downloads directory

     - Parameter now: If true, kills any active media management. Defaults to false
    */
    func shutdown() {
        config.logger.info("Shutting down monitrs.")
        config.stopMonitoring()
        moveOperationQueue.isSuspended = true
        convertOperationQueue.isSuspended = true
        if moveOperationQueue.operationCount > 0 {
            config.logger.info("Saving conversion queue")
            try? moveOperationQueue.save(to: config.configFile.parent + "moveOperationQueue.json")
        }
        if convertOperationQueue.operationCount > 0 {
            config.logger.info("Saving conversion queue")
            try? convertOperationQueue.save(to: config.configFile.parent + "convertOperationQueue.json")
        }
        moveOperationQueue.cancelAllOperations()
        convertOperationQueue.cancelAllOperations()
    }

	// MARK: - DirectorMonitor delegate method(s)

    /**
     Called when an event is triggered by the directory monitor

     - Parameter directoryMonitor: The DirectoryMonitor that triggered the event
    */
    func directoryMonitorDidObserveChange(_ directoryMonitor: DirectoryMonitor) {
        guard !isRunning else {
            needsUpdate = true
            return
        }
        // The FileSystem monitoring doesn't work on Linux yet, so only check
        //   if a write occurred in the directory if we're not on Linux
        #if !os(Linux)
        // Check that a new write occured
        guard directoryMonitor.directoryMonitorSource?.data == .write else {
            return
        }
        #endif
        self.run()
    }
}
