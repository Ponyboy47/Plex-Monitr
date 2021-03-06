/*

    MediaProtocol.swift

    Created By: Jacob Williams
    Description: This file contains the media protocol and error enum
    License: MIT License

*/

import Foundation
import PathKit
import Downpour
import SwiftShell

typealias Command = (command: String, args: [String], outputPath: Path, deleteOriginal: Bool)

// Media related errors
enum MediaError: Error {
    case unsupportedFormat(String)
    case alreadyExists(Path)
    case conversionError(String)
    case fileNotDeletable
    case unknownContainer(String)
    enum DownpourError: Error {
        case missingTVSeason(String)
        case missingTVEpisode(String)
    }
    enum FFProbeError: Error {
        case couldNotGetMetadata(String)
        case streamNotConvertible(to: CodecType, stream: FFProbeStreamProtocol)
    }
    enum VideoError: Error {
        case sampleMedia
        case invalidConfig
        case noStreams
    }
    enum AudioError: Error {
        case invalidConfig
        case noStreams
    }
}

enum MediaCodingKeys: String, CodingKey {
    case path
    case isHomeMedia
}

enum ConvertibleMediaCodingKeys: String, CodingKey {
    case path
    case isHomeMedia
    case unconvertedFile
}

enum MediaState {
    case moving
    case converting
    case deleting
    indirect case success(MediaState)
    indirect case failed(MediaState, Media)
    indirect case unconverted(MediaState)
    indirect case subtitle(MediaState, Video.Subtitle)
}

/// Protocol for the common implementation of Media types
protocol Media: class, Codable, CustomStringConvertible {
    /// The path to the media file
    var path: Path { get set }
    /// Whether the media file is home media or comercial
    var isHomeMedia: Bool { get set }
    /// Used to retrieve basic data from the file
    var downpour: Downpour { get set }
    /// The name of the file in the proper Plex standardized format
    var plexName: String { get }
    /// The plex filename (including it's extension)
    var plexFilename: String { get }
    /// The directory where the media should be placed within plex
    var finalDirectory: Path { get }
    /// The MainMonitr to notify when processing of a file has finished
    var mainMonitr: MainMonitr! { get set }
    /// an array of the supported extensions by the media type
    static var supportedExtensions: [String] { get }
    // swiftlint:disable identifier_name
    var _info: FFProbe? { get set }
    // swiftlint:enable identifier_name

    /// Initializer
    init(_ path: Path) throws
    /// Moves the media file to the finalDirectory
    func move(to plexPath: Path) throws -> MediaState
    /// Returns whether or not the Media type supports the given format
    static func isSupported(ext: String) -> Bool
    func info() throws -> FFProbe
}

extension Media {
    func info() throws -> FFProbe {
        if _info == nil {
            let ffprobeResponse = SwiftShell.run("ffprobe", ["-hide_banner", "-of", "json", "-show_streams", "\(path.absolute.string)"])

            guard ffprobeResponse.succeeded else {
                throw MediaError.FFProbeError.couldNotGetMetadata(ffprobeResponse.stderror)
            }
            guard !ffprobeResponse.stdout.isEmpty else {
                throw MediaError.FFProbeError.couldNotGetMetadata("File does not contain any metadata")
            }
            loggerQueue.async {
                logger.verbose("Got audio/video stream data for '\(self.path.absolute)'")
                logger.verbose("'\(self.path.absolute)' => '\(ffprobeResponse.stdout)'")
            }

            _info = try JSONDecoder().decode(FFProbe.self, from: ffprobeResponse.stdout.data(using: .utf8)!)
        }
        return _info!
    }

    var plexFilename: String {
        // Return the plexified name + it's extension
        return plexName + "." + (path.extension ?? "")
    }

    var description: String {
        return "\(type(of: self))(path: \(path), plexName: \(plexName))"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: MediaCodingKeys.self)

        try self.init(values.decode(Path.self, forKey: .path))
        self.isHomeMedia = try values.decode(Bool.self, forKey: .isHomeMedia)
    }

    static func isSupported(ext: String) -> Bool {
        return supportedExtensions.contains(ext.lowercased())
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: MediaCodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(isHomeMedia, forKey: .isHomeMedia)
    }

    internal func commonMove(to plexPath: Path) throws -> MediaState {
        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory

        // Create a path to the location where the file will RIP
        let finalRestingPlace = mediaDirectory + plexFilename

        guard path.absolute != finalRestingPlace.absolute else {
            loggerQueue.async {
                logger.warning("Media file is already located at it's final resting place")
            }
            return .success(.moving)
        }

        loggerQueue.async {
            logger.verbose("Preparing to move file: \(self.path.string)")
        }
        // Create the directory
        if !mediaDirectory.isDirectory {
            loggerQueue.async {
                logger.debug("Creating the media file's directory: \(mediaDirectory.string)")
            }
            try mediaDirectory.mkpath()
        }

        guard !finalRestingPlace.isFile else {
            throw MediaError.alreadyExists(finalRestingPlace)
        }

        loggerQueue.async {
            logger.debug("Moving media file '\(self.path.string)' => '\(finalRestingPlace)'")
        }
        // Move the file to the correct plex location
        try path.move(finalRestingPlace)
        // Change the path now to match
        path = finalRestingPlace
        loggerQueue.async {
            logger.verbose("Successfully moved file to '\(finalRestingPlace.string)'")
        }

        guard path.isFile else {
            loggerQueue.async {
                logger.error("Successfully moved the file, but there is no file located at the final resting place '\(self.path.string)'")
            }
            return .failed(.moving, self)
        }

        return .success(.moving)
    }

    func move(to plexPath: Path) throws -> MediaState {
        return try commonMove(to: plexPath)
    }
}

protocol ConvertibleMedia: Media {
    /// The path to the original media file (before it was converted)
    var unconvertedFile: Path? { get set }
    /// The config to use when converting the media
    var conversionConfig: ConversionConfig! { get set }
    /// Whether the media file has already been converted or not
    var beenConverted: Bool { get set }
    /// Moves the original media file to the finalDirectory
    func moveUnconverted(to plexPath: Path) throws -> MediaState
    /// Returns the command to be used for converting the media
    func convertCommand() throws -> Command
    /// Returns whether or not the Media type needs to be converted for Plex
    ///   DirectPlay capabilities to be enabled
    func needsConversion() throws -> Bool
}

extension ConvertibleMedia {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: ConvertibleMediaCodingKeys.self)

        try self.init(values.decode(Path.self, forKey: .path))
        self.isHomeMedia = try values.decode(Bool.self, forKey: .isHomeMedia)
        self.unconvertedFile = try values.decode(Path.self, forKey: .unconvertedFile)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ConvertibleMediaCodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(isHomeMedia, forKey: .isHomeMedia)
        try container.encode(unconvertedFile, forKey: .unconvertedFile)
    }

    func move(to plexPath: Path) throws -> MediaState {
        let convertedMediaState = try (self as Media).move(to: plexPath)
        switch convertedMediaState {
        case .success:
            return .unconverted(try self.moveUnconverted(to: plexPath))
        default:
            return convertedMediaState
        }
    }

    func moveUnconverted(to plexPath: Path) throws -> MediaState {
        guard let unconvertedPath = unconvertedFile else {
            loggerQueue.async {
                logger.verbose("No unconverted file to move")
            }
            return .success(.moving)
        }
        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory

        // Create a path to the location where the file will RIP
        let finalRestingPlace = mediaDirectory + "\(plexName) - original.\(unconvertedPath.extension ?? "")"

        guard path.absolute != finalRestingPlace.absolute else {
            loggerQueue.async {
                logger.warning("Unconverted media file is already located at it's final resting place")
            }
            return .success(.moving)
        }

        loggerQueue.async {
            logger.verbose("Preparing to move file: \(unconvertedPath.string)")
        }

        // Create the directory
        if !mediaDirectory.isDirectory {
            loggerQueue.async {
                logger.debug("Creating the media file's directory: \(mediaDirectory.string)")
            }
            try mediaDirectory.mkpath()
        }

        // Ensure the finalRestingPlace doesn't already exist
        guard !finalRestingPlace.isFile else {
            throw MediaError.alreadyExists(finalRestingPlace)
        }

        loggerQueue.async {
            logger.debug("Moving media file '\(unconvertedPath.string)' => '\(finalRestingPlace.string)'")
        }
        // Move the file to the correct plex location
        try unconvertedPath.move(finalRestingPlace)
        loggerQueue.async {
            logger.verbose("Successfully moved file to '\(finalRestingPlace.string)'")
        }
        // Change the path now to match
        unconvertedFile = finalRestingPlace

        guard unconvertedPath.isFile else {
            loggerQueue.async {
                logger.error("Successfully moved the file, but there is no file located at the final resting place '\(unconvertedPath.string)'")
            }
            return .failed(.moving, self)
        }

        return .success(.moving)
    }
}
