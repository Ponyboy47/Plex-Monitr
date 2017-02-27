import Foundation
import PathKit
import Async

class Monitr: DirectoryMonitorDelegate {
    private var config: Config
    private var isModifyingMedia: Bool = false {
        didSet {
            if !isModifyingMedia && needsUpdate {
                needsUpdate = false
                run()
            }
        }
    }
    private var needsUpdate: Bool = false

    init(_ config: Config) {
        self.config = config
    }

    public func run() {
        Async.background {
            self.isModifyingMedia = true
            defer {
                self.isModifyingMedia = false
            }
            let media = self.getMedia(from: self.config.torrentDirectory)
            if media.count > 0 {
                if let unmovedMedia = self.moveMedia(media) {
                    print("Failed to move media to plex:\n\t\(unmovedMedia)")
                }
            }
        }
    }

    public func startMonitoring() {
        // Begin watching the torrent downloads directory
        config.torrentWatcher?.startMonitoring()
    }

    public func shutdown(now: Bool = false) {
        config.torrentWatcher?.stopMonitoring()
        if now {
            // Kill any other stuff going on
        }
    }

    func getMedia(from path: Path) -> [Media] {
        do {
            // Get all the children in the torrent downloads directory
            let children = try path.recursiveChildren()
            var media: [Media] = []
            // Iterate of the children paths
            // Skips the directories and just checks for files
            for child in children where child.isFile {
                var m: Media?
                do {
                    m = try Video(child)
                } catch {
                    print("Failed to create video media object.\n\t\(error)")
                    do {
                        m = try Audio(child)
                    } catch {
                        print("Failed to create audio media object.\n\t\(error)")
                    }
                }
                if let _m = m {
                    media.append(_m)
                } else {
                    print("Unknown or unsupported file found: \(child)")
                }
            }
            return media
        } catch {
            print("Failed to get recursive children from the torrent directory.\n\t\(error)")
        }
        return []
    }

    func directoryMonitorDidObserveChange(_ directoryMonitor: DirectoryMonitor) {
        guard directoryMonitor.directoryMonitorSource?.data == .write else {
            needsUpdate = false
            return
        }
        guard !isModifyingMedia else {
            needsUpdate = true
            return
        }
        run()
    }

    func moveMedia(_ media: [Media]) -> [Media]? {
        var failedMedia: [Media]? = []

        for var m in media {
            do {
                try m.move(to: config.plexDirectory)
            } catch {
                print("Failed to move media: \(m)\n\t\(error)")
                failedMedia?.append(m)
            }
        }

        guard let failed = failedMedia?.count, failed > 0 else { return nil }

        return failedMedia
    }

    func convertMedia(_ media: [Media]) -> [Media]? {
        return nil
    }
}
