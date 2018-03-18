/*

    Monitr+Convertible.swift

    Created By: Jacob Williams
    Description: This file contains the Monitr class, which is used to continually check the 
                   downloads directory for new content and distribute it appropriately.
    License: MIT License

*/

import SwiftShell
import Dispatch

enum MonitrError: Error {
    case missingDependencies([Dependency])
}

enum Dependency: String {
    case handbrake = "HandBrakeCLI"
    case mp4v2 = "mp4track"
    case ffmpeg
    case mkvtoolnix = "mkvpropedit"
    case transcodeVideo = "transcode-video"

    static let all: [Dependency] = [.handbrake, .mp4v2, .ffmpeg, .mkvtoolnix, .transcodeVideo]
}

class ConvertibleMonitr<M>: Monitr<M> where M: ConvertibleMedia {
    var convertOperationQueue: MediaOperationQueue

    init(_ config: Config, moveOperationQueue: MediaOperationQueue, convertOperationQueue: MediaOperationQueue) throws {
        self.convertOperationQueue = convertOperationQueue

        try super.init(config, moveOperationQueue: moveOperationQueue)

        self.config.convert = config.convert

        if config.convert {
            try checkConversionDependencies()
        }
    }

    override func setupOperation(for media: M) -> MediaOperation<M>? {
        guard config.convert else {
            return super.setupOperation(for: media)
        }

        setupConversionConfig(media)

        let move = MoveOperation(media, logger: config.logger, plexDirectory: config.plexDirectory, deleteSubtitles: config.deleteSubtitles)

        guard !media.beenConverted else {
            return move
        }

        do {
            if try media.needsConversion(logger) {
                config.logger.verbose("Need to convert: \(media.path)")
                let convert = try ConvertOperation(media, logger: config.logger, prepareConversion: true)
                if config.convertImmediately {
                    convert.queuePriority = .veryHigh
                    move.addDependency(convert)
                } else {
                    convert.addDependency(move)
                    move.completionBlock = {
                        self.convertOperationQueue.addOperation(convert)
                    }
                    return convert
                }
            }
            return move
        } catch {
            config.logger.error("Could not determine if '\(media.path)' needs to be converted")
            config.logger.debug(error)
        }
        return nil
    }

    override func addToQueue(_ operation: MediaOperation<M>?) {
        guard let operation = operation else { return }

        if operation is ConvertOperation<M> {
            convertOperationQueue.addOperation(operation)

            for dependency in operation.dependencies {
                addToQueue(dependency as? MediaOperation<M>)
            }
        } else {
            super.addToQueue(operation)
        }
    }

    private func setupConversionConfig(_ media: ConvertibleMedia) {
        if media is Video {
            (media as! Video).conversionConfig = VideoConversionConfig(config: config)
        } else if media is Audio {
            (media as! Audio).conversionConfig = AudioConversionConfig(config: config)
        } else {
            config.logger.error("Unknown Convertible Media type from \(media.path)")
        }
    }

    private func checkConversionDependencies() throws {
        config.logger.verbose("Making sure we have the required dependencies for transcoding \(M.self) media...")

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
            throw MonitrError.missingDependencies(missing)
        }
    }
}
