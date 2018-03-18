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
final class Audio: ConvertibleMedia, Equatable {
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
        return false
    }

    static func == (lhs: Audio, rhs: Audio) -> Bool {
        return lhs.path == rhs.path
    }
    static func == <T: Media>(lhs: Audio, rhs: T) -> Bool {
        return lhs.path == rhs.path
    }
    static func == <T: Media>(lhs: T, rhs: Audio) -> Bool {
        return lhs.path == rhs.path
    }
}
