/*

    MediaProtocol.swift

    Created By: Jacob Williams
    Description: This file contains the media protocol and error enum
    License: MIT License

*/

import Foundation
import PathKit
import Downpour
import SwiftyBeaver
import JSON

// Media related errors
enum MediaError: Error {
    case unsupportedFormat(String)
    case notImplemented
    case alreadyExists(Path)
    case conversionError(String)
    case fileNotDeletable
    enum DownpourError: Error {
        case missingTVSeason(String)
        case missingTVEpisode(String)
    }
    enum FFProbeError: Error {
        case couldNotGetMetadata(String)
        case couldNotCreateFFProbe(String)
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

/// Protocol for the common implementation of Media types
protocol Media: class, JSONConvertible {
    /// The path to the media file
    var path: Path { get set }
    /// Used to retrieve basic data from the file
    var downpour: Downpour { get set }
    /// The name of the file in the proper Plex standardized format
    var plexName: String { get }
    /// The plex filename (including it's extension)
    var plexFilename: String { get }
    /// The directory where the media should be placed within plex
    var finalDirectory: Path { get }
    /// an array of the supported extensions by the media type
    static var supportedExtensions: [String] { get }

    /// Initializer
    init(_ path: Path) throws
    /// Moves the media file to the finalDirectory
    func move(to plexPath: Path, log: SwiftyBeaver.Type) throws -> Media
    /// Returns whether or not the Media type supports the given format
    static func isSupported(ext: String) -> Bool
}

extension Media {
    var plexFilename: String {
        // Return the plexified name + it's extension
        return plexName + "." + (path.extension ?? "")
    }

    /// JSONRepresentable protocol requirement
    func encoded() -> JSON {
        return [
            "path": path.string
        ]
    }

    init(json: JSON) throws {
        try self.init(Path(json.get("path")))
    }

    static func isSupported(ext: String) -> Bool {
        return supportedExtensions.contains(ext.lowercased())
    }

    func move(to plexPath: Path, log: SwiftyBeaver.Type) throws -> Media {
        // If it's already in the final directory then go ahead and return
        guard !path.string.contains(finalDirectory.string) else { return self }
        log.verbose("Preparing to move file: \(path.string)")
        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory
        // Create the directory
        if !mediaDirectory.isDirectory {
            log.verbose("Creating the media file's directory: \(mediaDirectory.string)")
            try mediaDirectory.mkpath()
        }

        // Create a path to the location where the file will RIP
        let finalRestingPlace = mediaDirectory + plexFilename

        guard path.absolute != finalRestingPlace.absolute else {
            log.info("Media file is already located at it's final resting place")
            return self
        }

        // Ensure the finalRestingPlace doesn't already exist
        guard !finalRestingPlace.isFile else {
            throw MediaError.alreadyExists(finalRestingPlace)
        }

        log.verbose("Moving media file '\(path.string)' => '\(finalRestingPlace.string)'")
        // Move the file to the correct plex location
        try path.move(finalRestingPlace)
        log.verbose("Successfully moved file to '\(finalRestingPlace.string)'")
        // Change the path now to match
        path = finalRestingPlace

        return self
    }
}

protocol ConvertibleMedia: Media {
    /// The path to the original media file (before it was converted). Only set when the original file is not to be deleted
    var unconvertedFile: Path? { get set }
    /// Moves the original media file to the finalDirectory
    func moveUnconverted(to plexPath: Path, log: SwiftyBeaver.Type) throws -> ConvertibleMedia
    /// Converts the media file to a Plex DirectPlay supported format
    func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws -> ConvertibleMedia
    /// Returns whether or not the Media type needs to be converted for Plex
    ///   DirectPlay capabilities to be enabled
    static func needsConversion(file: Path, with config: ConversionConfig, log: SwiftyBeaver.Type) throws -> Bool
}

extension ConvertibleMedia {
    func move(to plexPath: Path, log: SwiftyBeaver.Type) throws -> ConvertibleMedia {
        if let _ = unconvertedFile {
            return try ((self as Media).move(to: plexPath, log: log) as! ConvertibleMedia).moveUnconverted(to: plexPath, log: log)
        }
        return try (self as Media).move(to: plexPath, log: log) as! ConvertibleMedia
    }

    func moveUnconverted(to plexPath: Path, log: SwiftyBeaver.Type) throws -> ConvertibleMedia {
        guard let unconvertedPath = unconvertedFile else { return self }
        // If it's already in the final directory then go ahead and return
        guard !unconvertedPath.string.contains(finalDirectory.string) else { return self }

        log.verbose("Preparing to move file: \(unconvertedPath.string)")
        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory
        // Create the directory
        if !mediaDirectory.isDirectory {
            log.verbose("Creating the media file's directory: \(mediaDirectory.string)")
            try mediaDirectory.mkpath()
        }

        // Create a path to the location where the file will RIP
        let finalRestingPlace = mediaDirectory + "\(plexName) - original.\(unconvertedPath.extension ?? "")"

        guard path.absolute != finalRestingPlace.absolute else {
            log.info("Unconverted media file is already located at it's final resting place")
            return self
        }

        // Ensure the finalRestingPlace doesn't already exist
        guard !finalRestingPlace.isFile else {
            throw MediaError.alreadyExists(finalRestingPlace)
        }

        log.verbose("Moving media file '\(unconvertedPath.string)' => '\(finalRestingPlace.string)'")
        // Move the file to the correct plex location
        try unconvertedPath.move(finalRestingPlace)
        log.verbose("Successfully moved file to '\(finalRestingPlace.string)'")
        // Change the path now to match
        unconvertedFile = finalRestingPlace

        return self
    }

    /// JSONRepresentable protocol requirement
    func encoded() -> JSON {
        var json: JSON = (self as Media).encoded()
        if let uF = unconvertedFile {
            json["unconvertedFile"] = uF.string.encoded()
        }
        return json
    }
}
