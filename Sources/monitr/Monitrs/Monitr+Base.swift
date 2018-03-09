/*

    Monitr+Base.swift

    Created By: Jacob Williams
    Description: This file contains the Monitr class, which is used to continually check the 
                   downloads directory for new content and distribute it appropriately.
    License: MIT License

*/

import Foundation
import PathKit
import Cron
import SwiftyBeaver
import Dispatch

/// Checks the downloads directory for new content to add to Plex
class Monitr<M> where M: Media {
    /// The current version of monitr
    static var version: String { return "0.7.0" }

    /// The configuration to use for the monitor
    var config: Config

    var moveOperationQueue: MediaOperationQueue
    var convertOperationQueue: MediaOperationQueue
    var cronStart: CronJob!
    var cronEnd: CronJob!

    init(_ config: Config, moveOperationQueue: MediaOperationQueue, convertOperationQueue: MediaOperationQueue) throws {
        self.config = config
        self.moveOperationQueue = moveOperationQueue
        self.convertOperationQueue = convertOperationQueue

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

    /**
     Stop watching the downloads directory

     - Parameter now: If true, kills any active media management. Defaults to false
    */
    public func shutdown() {
        config.logger.info("Shutting down \(M.self) monitr.")
        moveOperationQueue.isSuspended = true
        convertOperationQueue.isSuspended = true
        if moveOperationQueue.operationCount > 0 {
            config.logger.info("Saving \(M.self) conversion queue")
            try? moveOperationQueue.save(to: config.configFile.parent + "moveOperationQueue.json")
        }
        if convertOperationQueue.operationCount > 0 {
            config.logger.info("Saving \(M.self) conversion queue")
            try? convertOperationQueue.save(to: config.configFile.parent + "convertOperationQueue.json")
        }
        moveOperationQueue.cancelAllOperations()
        convertOperationQueue.cancelAllOperations()
    }
}
