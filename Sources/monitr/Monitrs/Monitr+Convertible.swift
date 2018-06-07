/*

    Monitr+Convertible.swift

    Created By: Jacob Williams
    Description: This file contains the Monitr class, which is used to continually check the 
                   downloads directory for new content and distribute it appropriately.
    License: MIT License

*/

import SwiftShell
import Dispatch
import TaskKit

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
    override init(_ config: Config, moveTaskQueue: LinkedTaskQueue, convertTaskQueue: LinkedTaskQueue) throws {
        try super.init(config, moveTaskQueue: moveTaskQueue, convertTaskQueue: convertTaskQueue)

        self.config.convert = config.convert

        if config.convert {
            try checkConversionDependencies()
        }
    }

    override func setupTask(for media: M) -> MediaTask<M>? {
        guard config.convert else {
            return super.setupTask(for: media)
        }

        setupConversionConfig(media)

        let move = MoveTask(media, plexDirectory: config.plexDirectory, deleteSubtitles: config.deleteSubtitles, logger: config.logger)

        guard !media.beenConverted else {
            return move
        }

        do {
            if try media.needsConversion(logger) {
                config.logger.verbose("Need to convert: \(media.path)")
                var convert: ConversionTask<M>
                if config.convertImmediately {
                    convert = ConversionTask(media, priority: .high, logger: config.logger)
                    move.addDependency(convert)
                } else {
                    convert = ConversionTask(media, logger: config.logger)
                    convert.addDependency(move)
                    return convert
                }
            }
        } catch {
            config.logger.error("Could not determine if '\(media.path)' needs to be converted")
            config.logger.debug(error)
        }
        return move
    }

    override func addToQueue(_ task: MediaTask<M>?) {
        guard let task = task else { return }

        for dependency in task.dependencies {
            addToQueue(dependency as? MediaTask<M>)
        }

        if task is ConversionTask<M> {
            convertTaskQueue.add(task: task)
        } else {
            super.addToQueue(task)
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
