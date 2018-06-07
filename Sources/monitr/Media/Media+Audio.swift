/*

 AudioMedia.swift

 Created By: Jacob Williams
 Description: This file contains the Audio media structure for easy management of downloaded files
 License: MIT License

 */

import Foundation
import PathKit
import Downpour
import SwiftyBeaver

/// Management for Audio files
final class Audio: ConvertibleMedia {
    /// The supported extensions
    static var supportedExtensions: [String] = ["mp3", "m4a", "alac", "flac",
                                                "aac", "wav"]

    var path: Path
    var isHomeMedia: Bool = false
    var downpour: Downpour
    var unconvertedFile: Path?
    var conversionConfig: ConversionConfig!
    lazy var audioConversionConfig: AudioConversionConfig? = {
        conversionConfig as? AudioConversionConfig
    }()
    var beenConverted: Bool = false
    weak var mainMonitr: MainMonitr!
    //swiftlint:disable identifier_name
    var _info: FFProbe?
    //swiftlint:enable identifier_name

    var plexName: String {
        // Audio files are usually pretty simple
        return path.lastComponentWithoutExtension
    }
    var finalDirectory: Path {
        // Music goes in the Music + Artist + Album directory
        var base: Path = "Music"
        guard let artist = downpour.artist else { return base + "Unknown" }
        base += artist
        guard let album = downpour.album else { return base + "Unknown" }
        base += album
        return base
    }

    init(_ path: Path) throws {
        guard Audio.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(path.extension ?? "")
        }
        // Set the media file's path to the absolute path
        self.path = path.absolute
        self.unconvertedFile = path.absolute
        // Create the downpour object
        self.downpour = Downpour(fullPath: path.absolute)
    }

    func convertCommand(_ logger: SwiftyBeaver.Type) throws -> Command {
        fatalError("Not Implemented")
    }

    func needsConversion(_ logger: SwiftyBeaver.Type) throws -> Bool {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable audio (if necessary)
        guard let config = audioConversionConfig else {
            throw MediaError.AudioError.invalidConfig
        }
        logger.verbose("Getting audio stream data for '\(path.absolute)'")

        let ffprobe = try info()

        var audioStreams = ffprobe.audioStreams

        let mainAudioStream: AudioStream

        if audioStreams.count > 1 {
            logger.warning("Multiple audio streams found, trying to identify the main one...")
            mainAudioStream = identifyMainAudioStream(audioStreams, using: config)
        } else if audioStreams.count == 1 {
            mainAudioStream = audioStreams[0]
        } else {
            throw MediaError.AudioError.noStreams
        }

        logger.verbose("Got main audio/video streams. Checking if we need to convert them")
        return try needToConvert(audioStream: mainAudioStream, logger: logger)
    }

    private func needToConvert(audioStream: AudioStream, logger: SwiftyBeaver.Type) throws -> Bool {
        guard let config = audioConversionConfig else {
            throw MediaError.AudioError.invalidConfig
        }

        logger.verbose("Streams:\n\nAudio:\n\(audioStream.description)")

        guard let container = AudioContainer(rawValue: path.extension ?? "") else {
            throw MediaError.unknownContainer(path.extension ?? "")
        }

        guard container == config.audioContainer else { return true }
        guard let audioCodec = audioStream.codec as? AudioCodec, config.codec == .any || audioCodec == config.codec else { return true }

        logger.verbose("\(path) does not need to be converted")
        return false
    }

    private func identifyMainAudioStream(_ audioStreams: [AudioStream], using config: AudioConversionConfig) -> AudioStream {
        return audioStreams.reduce(audioStreams[0]) { mainStream, nextStream in
            if mainStream.channels > nextStream.channels {
                return mainStream
            } else if mainStream.channelLayout > nextStream.channelLayout {
                return mainStream
            } else if mainStream.bitRate > nextStream.bitRate {
                return mainStream
            } else if mainStream.sampleRate > nextStream.sampleRate {
                return mainStream
            } else if mainStream.codec as? AudioCodec != nextStream.codec as? AudioCodec {
                if mainStream.codec as? AudioCodec == config.codec {
                    return mainStream
                } else if nextStream.codec as? AudioCodec != config.codec && mainStream.index < nextStream.index {
                    return mainStream
                }
            } else if mainStream.index < nextStream.index {
                return mainStream
            }
            return nextStream
        }
    }
}

fileprivate extension Optional where Wrapped: Comparable {
    static func > (lhs: Wrapped?, rhs: Wrapped?) -> Bool {
        if let left = lhs, let right = rhs {
            return left > right
        }
        return false
    }
}
