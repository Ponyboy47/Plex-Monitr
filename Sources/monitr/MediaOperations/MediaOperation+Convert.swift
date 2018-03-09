//
//  MediaOperation+Convert.swift
//  Plex-MonitrPackageDescription
//
//  Created by Jacob Williams on 03/01/18.
//

import SwiftyBeaver
import Foundation
import SwiftShell
import PathKit

class ConvertOperation<MediaType: ConvertibleMedia>: MediaOperation<MediaType> {
    var command: AsyncCommand!
    var commandName: String
    var commandArgs: [String]
    var outputPath: Path
    var deleteOriginal: Bool

    private enum ConvertCodingKeys: String, CodingKey {
        case commandName
        case commandArgs
        case outputPath
        case deleteOriginal
    }

    override init(_ media: MediaType, logger: SwiftyBeaver.Type) {
        fatalError("Use the throwable initializer init(_ media:logger:prepareConversion:)")
    }

    init(_ media: MediaType, logger: SwiftyBeaver.Type, prepareConversion: Bool) throws {
        let (cmd, args, oP, dO) = try media.convertCommand(logger)
        commandName = cmd
        commandArgs = args
        outputPath = oP
        deleteOriginal = dO
        super.init(media, logger: logger)
        self.qualityOfService = .utility
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: ConvertCodingKeys.self)

        commandName = try values.decode(String.self, forKey: .commandName)
        commandArgs = try values.decode([String].self, forKey: .commandArgs)
        outputPath = try values.decode(Path.self, forKey: .outputPath)
        deleteOriginal = try values.decode(Bool.self, forKey: .deleteOriginal)
        try super.init(from: decoder)
        self.qualityOfService = .utility
    }

    override var isAsynchronous: Bool {
        return true
    }

    override var isExecuting: Bool {
        return command.isRunning
    }

    override var isFinished: Bool {
        return !command.isRunning
    }

    override var isCancelled: Bool {
        return wasCancelled
    }
    var wasCancelled: Bool = false

    override func start() {
        guard isReady else {
            return
        }
        if !dependencies.isEmpty {
            media = (dependencies.first! as! MediaOperation).media
        }

        command = SwiftShell.runAsync(commandName, commandArgs)
        main()
    }

    override func main() {
        command.stdout.read()
        self.didChangeValue(forKey: "isExecuting")
        self.didChangeValue(forKey: "isFinished")
        logger.debug("Finished conversion of media file '\(media.path)'")

        do {
			guard command.exitcode() == 0 else {
				var error: String = "Error attempting to convert: \(media.path)"
				error += "\n\tCommand: \(commandName) \(commandArgs.joined(separator: " "))\n\tResponse: \(command.exitcode())"
				if !command.stdout.read().isEmpty {
					error += "\n\tStandard Out: \(command.stdout.read())"
				}
				if !command.stderror.read().isEmpty {
					error += "\n\tStandard Error: \(command.stderror.read())"
				}
				throw MediaError.conversionError(error)
			}

			logger.verbose("Successfully converted media file '\(media.path)' to '\(outputPath)'")

			if deleteOriginal {
                logger.debug("Deleting original file '\(media.path)'")
				try media.path.delete()
				logger.verbose("Successfully deleted original media file '\(media.path)'")
			} else {
				media.unconvertedFile = media.path
			}

			// Update the media object's path
			media.path = outputPath

			media.beenConverted = true
        } catch {
            logger.error("Error while converting \(MediaType.self) media")
            logger.debug(error)
        }
    }

    override func cancel() {
        command.stop()
        wasCancelled = true
        self.didChangeValue(forKey: "isExecuting")
        self.didChangeValue(forKey: "isCancelled")
    }
}
