import TaskKit
import SwiftyBeaver
import SwiftShell
import PathKit

class ConversionTask<MediaType: ConvertibleMedia>: MediaTask<MediaType>, ConfigurableTask, CancellableTask, PausableTask {
    var command: AsyncCommand!
    var commandName: String!
    var commandArgs: [String] = []
    var outputPath: Path!
    var deleteOriginal: Bool!

    // swiftlint:disable identifier_name
    func configure() -> Bool {
        do {
            let (cmd, args, oP, dO) = try media.convertCommand(logger)
            commandName = cmd
            commandArgs = args
            outputPath = oP
            deleteOriginal = dO
        } catch {
            logger.error("Failed to generate the conversion command for \(media.path)")
            logger.debug(error)
            return false
        }

        return true
    }
    // swiftlint:enable identifier_name

    override func execute() -> Bool {
        command = SwiftShell.runAsync(commandName, commandArgs)
        command.stdout.readData()
        logger.debug("Finished conversion of media file '\(media.path)'")

        guard command.exitcode() == 0 else {
            var error: String = "Error attempting to convert: \(media.path)"
            error += "\n\tCommand: \(commandName) \(commandArgs.joined(separator: " "))\n\tResponse: \(command.exitcode())"
            if !command.stdout.read().isEmpty {
                error += "\n\tStandard Out: \(command.stdout.read())"
            }
            if !command.stderror.read().isEmpty {
                error += "\n\tStandard Error: \(command.stderror.read())"
            }
            logger.error("Error converting \(MediaType.self) media")
            logger.debug(MediaError.conversionError(error))

            return false
        }

        logger.verbose("Successfully converted media file '\(media.path)' to '\(outputPath)'")

        do {
			if deleteOriginal {
                logger.debug("Deleting original file '\(media.path)'")
				try media.path.delete()
				logger.verbose("Successfully deleted original media file '\(media.path)'")
			}

			// Update the media object's path
			media.path = outputPath

			media.beenConverted = true
        } catch {
            logger.error("Error deleting the original file '\(media.path)'")
            logger.debug(error)
        }

        return true
    }

    func resume() -> Bool {
        return command.resume()
    }

    func pause() -> Bool {
        return command.suspend()
    }

    func cancel() -> Bool {
        command.stop()
        return true
    }
}
