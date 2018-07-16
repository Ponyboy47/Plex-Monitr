import Dispatch
import PathKit
import Cron
import TaskKit

final class MainMonitr: DirectoryMonitorDelegate {
    /// The current version of monitr
    static var version: String { return "0.8.0" }

    let videoMonitr: ConvertibleMonitr<Video>
    let audioMonitr: ConvertibleMonitr<Audio>
    let ignoreMonitr: Monitr<Ignore>

    let config: Config

    let queue = DispatchQueue(label: "com.monitr.main", qos: .userInitiated, attributes: .concurrent)
    let moveTaskQueue: LinkedTaskQueue
    let convertTaskQueue: LinkedTaskQueue
    private let _sem =  DispatchSemaphore(value: 1)

    var cronStart: CronJob!
    var cronEnd: CronJob!

    var currentMedia: [Media] = []

    var isRunning = false {
        didSet {
            // If we went from running to not running and needsUpdate is true, then we should run again just in case
            if oldValue && !isRunning && needsUpdate {
                needsUpdate = false
                self.run()
            }
        }
    }
    var needsUpdate = false

    init(config: Config) throws {
        self.moveTaskQueue = LinkedTaskQueue(name: "com.monitr.move", maxSimultaneous: 5)
        self.convertTaskQueue = LinkedTaskQueue(name: "com.monitr.convert", maxSimultaneous: config.convertThreads, linkedTo: self.moveTaskQueue)

        self.config = config

        videoMonitr = try ConvertibleMonitr<Video>(config, moveTaskQueue: moveTaskQueue, convertTaskQueue: convertTaskQueue)
        audioMonitr = try ConvertibleMonitr<Audio>(config, moveTaskQueue: moveTaskQueue, convertTaskQueue: convertTaskQueue)
        ignoreMonitr = try Monitr<Ignore>(config, moveTaskQueue: moveTaskQueue, convertTaskQueue: convertTaskQueue)

        moveTaskQueue.start()
        if config.convert {
            convertTaskQueue.start()
            if !config.convertImmediately {
                convertTaskQueue.pause()
                loggerQueue.async {
                    logger.verbose("Setting up the conversion queue cron jobs")
                }
                cronStart = CronJob(pattern: config.convertCronStart, queue: .global(qos: .background)) {
                    self.convertTaskQueue.resume()
                }
                cronEnd = CronJob(pattern: config.convertCronEnd, queue: .global(qos: .background)) {
                    self.convertTaskQueue.pause()
                }
                let next = MediaDuration(double: cronStart!.pattern.next(Date())!.date!.timeIntervalSinceNow)
                loggerQueue.async {
                    logger.verbose("Set up the conversion cron jobs! It will begin in \(next.description)")
                }
            }
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
        _sem.wait()
        isRunning = true

        defer { isRunning = false }

        var media = getAllMedia(from: config.downloadDirectories)
        let homeMedia = getAllMedia(from: config.homeVideoDownloadDirectories)

        // Get all the media in the downloads directory
        setHomeMedia(homeMedia)
        media += homeMedia

        // Remove items that we're currently processing
        // swiftlint:disable identifier_name
        media = media.filter { m in
            !currentMedia.contains(where: { c in
                var isEqual = false
                let mUnconverted = (m as? ConvertibleMedia)?.unconvertedFile?.absolute
                let cUnconverted = (c as? ConvertibleMedia)?.unconvertedFile?.absolute
                if let mU = mUnconverted, let cU = cUnconverted {
                    isEqual = mU == cU
                } else if let mU = mUnconverted {
                    isEqual = mU == c.path.absolute
                } else if let cU = cUnconverted {
                    isEqual = cU == m.path.absolute
                }
                return isEqual || m.path.absolute == c.path.absolute || m.plexName == c.plexName
            })
        }
        // swiftlint:enable identifier_name

        // If there's no new media, don't continue
        guard !media.isEmpty else { return }
        loggerQueue.async {
            logger.debug("Found \(media.count) total media files in the downloads directories")
        }

        currentMedia += media

        loggerQueue.async {
            logger.info("Found \(media.count) new media files to process")
        }
        _sem.signal()

        let videoMedia = media.compactMap { $0 as? Video }
        let audioMedia = media.compactMap { $0 as? Audio }
        let ignoredMedia = media.compactMap { $0 as? Ignore }

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
                        loggerQueue.async {
                            logger.warning("Unknown/unsupported file found: \(childFile)")
                        }
                    }
                }
                // swiftlint:enable identifier_name
            } catch {
                loggerQueue.async {
                    logger.error("Failed to get files from the downloads directories.")
                    logger.debug(error)
                }
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
                            video.findSubtitles(below: base)
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
            loggerQueue.async {
                logger.error("Error occured trying to create media object from '\(file)'.")
                logger.debug(error)
            }
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
        loggerQueue.sync {
            logger.info("Shutting down monitrs.")
        }
        config.stopMonitoring()
        if !convertTaskQueue.isDone {
            convertTaskQueue.cancel()
        }
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
