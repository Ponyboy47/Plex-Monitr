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
final class Audio: BaseConvertibleMedia {
    /// The supported extensions
    enum SupportedExtension: String {
        case mp3
        case m4a
        case alac
        case flac
        case aac
        case wav
    }

    override var plexName: String {
        // Audio files are usually pretty simple
        return path.lastComponentWithoutExtension
    }
    override var finalDirectory: Path {
        // Music goes in the Music + Artist + Album directory
        var base: Path = "Music"
        guard let artist = downpour.artist else { return base + "Unknown" }
        base += artist
        guard let album = downpour.album else { return base + "Unknown" }
        base += album
        return base
    }

    required init(_ path: Path) throws {
        guard Audio.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(path.extension ?? "")
        }
        try super.init(path)
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        let p = Path(try json.get("path"))
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Audio.isSupported(ext: p.extension ?? "") else {
            throw MediaError.unsupportedFormat(p.extension ?? "")
        }
        try super.init(json: json)
    }

    override func move(to plexPath: Path, log: SwiftyBeaver.Type) throws {
        try super.move(to: plexPath, log: log)
    }

    override func moveUnconverted(to plexPath: Path, log: SwiftyBeaver.Type) throws {
        try super.moveUnconverted(to: plexPath, log: log)
    }

    override func convert(_ conversionConfig: ConversionConfig?, _ log: SwiftyBeaver.Type) throws {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable audio (if necessary)
        guard let config = conversionConfig as? AudioConversionConfig else {
            throw MediaError.AudioError.invalidConfig
        }
        try convert(config, log)
    }

    func convert(_ conversionConfig: AudioConversionConfig, _ log: SwiftyBeaver.Type) throws {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable audio (if necessary)
        return
    }

    override class func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }

    override class func needsConversion(file: Path, with config: ConversionConfig, log: SwiftyBeaver.Type) throws -> Bool {
        return false
    }
}
