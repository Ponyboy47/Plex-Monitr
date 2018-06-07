import TaskKit
import PathKit
import SwiftyBeaver
import Dispatch

final class MoveTask<MediaType: Media>: MediaTask<MediaType> {
    let plexDirectory: Path
    let deleteSubtitles: Bool

    @available(*, renamed: "init")
    override init(_ media: MediaType, qos: DispatchQoS, priority: TaskPriority, logger: SwiftyBeaver.Type) {
        fatalError("Call init(_:MediaType,plexDirectory:Path,deleteSubtitles:Bool,logger:SwiftyBeaver.Type) instead")
    }

    init(_ media: MediaType, plexDirectory: Path, deleteSubtitles: Bool, priority: TaskPriority = .minimal, logger: SwiftyBeaver.Type) {
        self.plexDirectory = plexDirectory
        self.deleteSubtitles = deleteSubtitles
        super.init(media, qos: .background, priority: priority, logger: logger)
    }

    override func execute() -> Bool {
        logger.debug("Moving \(media.path)")

        do {
            let state: MediaState = try media.move(to: plexDirectory, logger: logger)

            switch state {
            case .subtitle(_, let sub):
                logger.warning("Failed to move subtitle '\(sub.path)' to plex")
                return false
            case .unconverted(.failed(_, let uMedia)):
                logger.warning("Failed to move unconverted \(MediaType.self) media '\(uMedia.path)' to plex")
                return false
            case .failed(.moving, let file):
                logger.warning("Failed to move \(MediaType.self) media '\(file.path)' to plex")
                return false
            case .failed(.deleting, let file):
                logger.warning("Failed to delete \(MediaType.self) media '\(file.path)'")
                return false
            default: break
            }
        } catch {
            logger.error("Failed to move '\(media.path)'")
            logger.debug(error)
            return false
        }

        do {
            if deleteSubtitles && media is Video {
                logger.verbose("Removing subtitles")
                try (media as! Video).deleteSubtitles()
            }
        } catch {
            logger.error("Failed to delete subtitles from : \(media.path)")
            logger.debug(error)
        }

        return true
    }
}
