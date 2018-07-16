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
            let (cmd, args, oP, dO) = try media.convertCommand()
            commandName = cmd
            commandArgs = args
            outputPath = oP
            deleteOriginal = dO
        } catch {
            loggerQueue.async {
                logger.error("Failed to generate the conversion command for \(self.media.path)")
                logger.debug(error)
            }
            return false
        }

        return true
    }
    // swiftlint:enable identifier_name

    override func execute() -> Bool {
        command = SwiftShell.runAsync(commandName, commandArgs)
        command.stdout.readData()
        loggerQueue.async {
            logger.debug("Finished conversion of media file '\(self.media.path)'")
        }

        guard command.exitcode() == 0 else {
            var error: String = "Error attempting to convert: \(media.path)"
            error += "\n\tCommand: \(commandName) \(commandArgs.joined(separator: " "))\n\tResponse: \(command.exitcode())"
            if !command.stdout.read().isEmpty {
                error += "\n\tStandard Out: \(command.stdout.read())"
            }
            if !command.stderror.read().isEmpty {
                error += "\n\tStandard Error: \(command.stderror.read())"
            }
            loggerQueue.async {
                logger.error("Error converting \(MediaType.self) media")
                logger.debug(MediaError.conversionError(error))
            }

            return false
        }

        loggerQueue.async {
            logger.verbose("Successfully converted media file '\(self.media.path)' to '\(self.outputPath)'")
        }

        do {
			if deleteOriginal {
                loggerQueue.async {
                    logger.debug("Deleting original file '\(self.media.path)'")
                }
				try media.path.delete()
                loggerQueue.async {
                    logger.verbose("Successfully deleted original media file '\(self.media.path)'")
                }
			}

			// Update the media object's path
			media.path = outputPath

			media.beenConverted = true
        } catch {
            loggerQueue.async {
                logger.error("Error deleting the original file '\(self.media.path)'")
                logger.debug(error)
            }
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
