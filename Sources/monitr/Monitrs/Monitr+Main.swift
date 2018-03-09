import Foundation
import Dispatch
import Async
import PathKit

final class MainMonitr: DirectoryMonitorDelegate {
    let videoMonitr: ConvertibleMonitr<Video>
    let audioMonitr: ConvertibleMonitr<Audio>
    let ignoreMonitr: Monitr<Ignore>
    let config: Config
    let queue: DispatchQueue = DispatchQueue(label: "MainMonitrQueue", qos: .userInitiated, attributes: .concurrent)
    let moveOperationQueue: MediaOperationQueue
    let convertOperationQueue: MediaOperationQueue

    var currentMedia: [Media] = []

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
        ignoreMonitr = try Monitr<Ignore>(config, moveOperationQueue: moveOperationQueue, convertOperationQueue: convertOperationQueue)
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
                return m.path == c.path
            })
        }
        // swiftlint:enable identifier_name

        currentMedia += media

        config.logger.info("Found \(media.count) new media files to process")

        let videoMedia = media.filter { $0 is Video }.map { $0 as! Video }
        let audioMedia = media.filter { $0 is Audio }.map { $0 as! Audio }
        let ignoredMedia = media.filter { $0 is Ignore }.map { $0 as! Ignore }

        Async.custom(queue: queue) {
            self.videoMonitr.run(videoMedia)
        }

        Async.custom(queue: queue) {
            self.audioMonitr.run(audioMedia)
        }

        Async.custom(queue: queue) {
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

    func shutdown() {
        self.config.stopMonitoring()
        videoMonitr.shutdown()
        audioMonitr.shutdown()
        ignoreMonitr.shutdown()
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
            return
        }
        #endif
        self.run()
    }
}
