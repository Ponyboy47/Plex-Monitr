import TaskKit
import PathKit
import SwiftyBeaver
import Dispatch

final class MoveTask<MediaType: Media>: MediaTask<MediaType> {
    let plexDirectory: Path
    let deleteSubtitles: Bool

    @available(*, renamed: "init")
    override init(_ media: MediaType, qos: DispatchQoS, priority: TaskPriority) {
        fatalError("Call init(_:MediaType,plexDirectory:Path,deleteSubtitles:Bool) instead")
    }

    init(_ media: MediaType, plexDirectory: Path, deleteSubtitles: Bool, priority: TaskPriority = .minimal) {
        self.plexDirectory = plexDirectory
        self.deleteSubtitles = deleteSubtitles
        super.init(media, qos: .background, priority: priority)
    }

    override func execute() -> Bool {
        loggerQueue.async {
            logger.debug("Moving \(self.media.path)")
        }

        do {
            let state: MediaState = try media.move(to: plexDirectory)

            switch state {
            case .subtitle(_, let sub):
                loggerQueue.async {
                    logger.warning("Failed to move subtitle '\(sub.path)' to plex")
                }
                return false
            case .unconverted(.failed(_, let uMedia)):
                loggerQueue.async {
                    logger.warning("Failed to move unconverted \(MediaType.self) media '\(uMedia.path)' to plex")
                }
                return false
            case .failed(.moving, let file):
                loggerQueue.async {
                    logger.warning("Failed to move \(MediaType.self) media '\(file.path)' to plex")
                }
                return false
            case .failed(.deleting, let file):
                loggerQueue.async {
                    logger.warning("Failed to delete \(MediaType.self) media '\(file.path)'")
                }
                return false
            default: break
            }
        } catch {
            loggerQueue.async {
                logger.error("Failed to move '\(self.media.path)'")
                logger.debug(error)
            }
            return false
        }

        do {
            if deleteSubtitles && media is Video {
                loggerQueue.async {
                    logger.verbose("Removing subtitles")
                }
                try (media as! Video).deleteSubtitles()
            }
        } catch {
            loggerQueue.async {
                logger.error("Failed to delete subtitles from : \(self.media.path)")
                logger.debug(error)
            }
        }

        return true
    }
}
