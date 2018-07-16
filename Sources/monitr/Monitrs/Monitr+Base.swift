/*

    Monitr+Base.swift

    Created By: Jacob Williams
    Description: This file contains the Monitr class, which is used to continually check the 
                   downloads directory for new content and distribute it appropriately.
    License: MIT License

*/
import TaskKit

/// Checks the downloads directory for new content to add to Plex
class Monitr<M> where M: Media {
    /// The configuration to use for the monitor
    var config: Config

    var moveTaskQueue: LinkedTaskQueue
    var convertTaskQueue: LinkedTaskQueue

    init(_ config: Config, moveTaskQueue: LinkedTaskQueue, convertTaskQueue: LinkedTaskQueue) throws {
        self.config = config
        self.moveTaskQueue = moveTaskQueue
        self.convertTaskQueue = convertTaskQueue

        // Since this media is not convertible, let's just set this false and not deal with it
        self.config.convert = false
    }

    func setupTask(for media: M) -> MediaTask<M>? {
        return MoveTask(media, plexDirectory: config.plexDirectory, deleteSubtitles: config.deleteSubtitles)
    }

    /// Gets all media object and moves them to Plex then deletes all the empty
    ///   directories left in the downloads directory
    func run(_ media: [M]) {
        guard !media.isEmpty else { return }
        loggerQueue.async {
            logger.info("\(media.count) new \(M.self) files")
            logger.verbose(media.map { $0.path })
        }

        for media in media {
            addToQueue(setupTask(for: media))
        }
    }

    func addToQueue(_ task: MediaTask<M>?) {
        guard let task = task else { return }

        for dependency in task.dependencies {
            addToQueue(dependency as? MediaTask<M>)
        }

        if task is MoveTask<M> {
            moveTaskQueue.add(task: task)
        } else {
            loggerQueue.async {
                logger.warning("Unknown operation type '\(type(of: task))'")
            }
        }
    }
}
