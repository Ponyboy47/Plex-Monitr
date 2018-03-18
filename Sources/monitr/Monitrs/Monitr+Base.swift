/*

    Monitr+Base.swift

    Created By: Jacob Williams
    Description: This file contains the Monitr class, which is used to continually check the 
                   downloads directory for new content and distribute it appropriately.
    License: MIT License

*/

/// Checks the downloads directory for new content to add to Plex
class Monitr<M> where M: Media {
    /// The configuration to use for the monitor
    var config: Config

    var moveOperationQueue: MediaOperationQueue

    init(_ config: Config, moveOperationQueue: MediaOperationQueue) throws {
        self.config = config
        self.moveOperationQueue = moveOperationQueue

        // Since this media is not convertible, let's just set this false and not deal with it
        self.config.convert = false
    }

    func setupOperation(for media: M) -> MediaOperation<M>? {
        return MoveOperation(media, logger: config.logger, plexDirectory: config.plexDirectory, deleteSubtitles: config.deleteSubtitles)
    }

    /// Gets all media object and moves them to Plex then deletes all the empty
    ///   directories left in the downloads directory
    func run(_ media: [M]) {
        guard !media.isEmpty else { return }
        config.logger.info("\(media.count) new \(M.self) files")
        config.logger.verbose(media.map { $0.path })

        for media in media {
            addToQueue(setupOperation(for: media))
        }
    }

    func addToQueue(_ operation: MediaOperation<M>?) {
        guard let operation = operation else { return }

        if operation is MoveOperation<M> {
            moveOperationQueue.addOperation(operation)

            for dependency in operation.dependencies {
                addToQueue(dependency as? MediaOperation<M>)
            }
        } else {
            config.logger.warning("Unknown operation type '\(type(of: operation))'")
        }
    }
}
