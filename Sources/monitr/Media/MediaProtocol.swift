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
    case sampleMedia
    case alreadyExists(Path)
    case conversionError(String)
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
        case invalidConfig
        case noStreams
    }
    enum AudioError: Error {
        case invalidConfig
        case noStreams
    }
}

/// Protocol for the common implementation of Media types
protocol Media: class, JSONInitializable, JSONRepresentable {
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

    /// Initializer
    init(_ path: Path) throws
    /// Moves the media file to the finalDirectory
    func move(to plexPath: Path, log: SwiftyBeaver.Type) throws
    /// Returns whether or not the Media type supports the given format
    static func isSupported(ext: String) -> Bool
}

protocol ConvertibleMedia: Media {
    /// The path to the original media file (before it was converted). Only set when the original file is not to be deleted
    var unconvertedFile: Path? { get set }
    /// Moves the original media file to the finalDirectory
    func moveUnconverted(to plexPath: Path, log: SwiftyBeaver.Type) throws
    /// Converts the media file to a Plex DirectPlay supported format
    func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws
    /// Returns whether or not the Media type needs to be converted for Plex
    ///   DirectPlay capabilities to be enabled
    static func needsConversion(file: Path, with config: ConversionConfig, log: SwiftyBeaver.Type) throws -> Bool
}
