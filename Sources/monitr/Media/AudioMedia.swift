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
import JSON

/// Management for Audio files
final class Audio: ConvertibleMedia {
    /// The supported extensions
    static var supportedExtensions: [String] = ["mp3", "m4a", "alac", "flac",
                                                "aac", "wav"]

    var path: Path
    var downpour: Downpour
    var unconvertedFile: Path?

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

    func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws -> ConvertibleMedia {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable audio (if necessary)
        guard let config = conversionConfig as? AudioConversionConfig else {
            throw MediaError.AudioError.invalidConfig
        }
        return try convert(config, log)
    }

    func convert(_ conversionConfig: AudioConversionConfig, _ log: SwiftyBeaver.Type) throws -> ConvertibleMedia {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable audio (if necessary)
        return self
    }

    class func needsConversion(file: Path, with config: ConversionConfig, log: SwiftyBeaver.Type) throws -> Bool {
        return false
    }
}
