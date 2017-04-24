/*

    Media.swift

    Created By: Jacob Williams
    Description: This file contains the media structures for easy management of downloaded files
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
    enum Downpour: Error {
        case missingTVSeason(String)
        case missingTVEpisode(String)
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
    func move(to newDirectory: Path, log: SwiftyBeaver.Type) throws -> Self
    /// Converts the media file to a Plex DirectPlay supported format
    func convert(_ log: SwiftyBeaver.Type?) throws -> Self
    /// Returns whether or not the Media type supports the given format
    static func isSupported(ext: String) -> Bool
    /// Returns whether or not the Media type needs to be converted for Plex
    ///   DirectPlay capabilities to be enabled
    static func needsConversion(file: Path) -> Bool
}

class BaseMedia: Media {
    var path: Path
    var downpour: Downpour
    var plexName: String {
        return downpour.title.wordCased
    }
    var plexFilename: String {
        // Return the plexified name + it's extension
        return plexName + "." + (path.extension ?? "")
    }
    var finalDirectory: Path {
        return ""
    }

    required init(_ path: Path) throws {
        // Set the media file's path to the absolute path
        self.path = path.absolute
        // Create the downpour object
        downpour = Downpour(fullPath: path)
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        // Set the media file's path to the absolute path
        path = Path(try json.get("path")).absolute
        // Create the downpour object
        downpour = Downpour(fullPath: path)
    }

    func move(to plexPath: Path, log: SwiftyBeaver.Type) throws -> Self {
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

    func convert(_ log: SwiftyBeaver.Type? = nil) throws -> Self {
        throw MediaError.notImplemented
        return self
    }

    class func isSupported(ext: String) -> Bool {
        print("isSupported(ext: String) is not implemented!")
        return false
    }

    class func needsConversion(file: Path) -> Bool {
        print("needsConversion(file: Path) is not implemented!")
        return false
    }

    /// JSONRepresentable protocol requirement
    func encoded() -> JSON {
        return [
            "path": path.string
        ]
    }
}

/// Management for Video files
final class Video: BaseMedia {
    /// The supported extensions
    enum SupportedExtension: String {
        case mp4
        case mkv
        case m4v
        case avi
        case wmv
    }

    // Lazy vars so these are calculated only once

    override var plexName: String {
        var name: String
        switch downpour.type {
            // If it's a movie file, plex wants "Title (YYYY)"
            case .movie:
                name = "\(downpour.title.wordCased)"
                if let year = downpour.year {
                    name += " (\(year))"
                }
            // If it's a tv show, plex wants "Title - sXXeYY"
            case .tv:
                name = "\(downpour.title.wordCased) - s\(String(format: "%02d", Int(downpour.season!)!))e\(String(format: "%02d", Int(downpour.episode!)!))"
            // Otherwise just return the title (shouldn't ever actually reach this)
            default:
                name = downpour.title.wordCased
        }
        // Return the calulated name
        return name
    }
    override var finalDirectory: Path {
        var base: Path
        switch downpour.type {
        case .movie:
            base = Path("Movies\(Path.separator)\(plexName)")
        case .tv:
            base = Path("TV Shows\(Path.separator)\(downpour.title.wordCased)\(Path.separator)Season \(String(format: "%02d", Int(downpour.season!)!))\(Path.separator)\(plexName)")
        default:
            base = ""
        }
        return base
    }

    required init(_ path: Path) throws {
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Video.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(path.extension ?? "")
        }
        guard !path.string.lowercased().contains("sample") else {
            throw MediaError.sampleMedia
        }

        try super.init(path)

        if downpour.type == .tv {
            guard let _ = downpour.season else {
                throw MediaError.Downpour.missingTVSeason(path.string)
            }
            guard let _ = downpour.episode else {
                throw MediaError.Downpour.missingTVEpisode(path.string)
            }
        }
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        let p = Path(try json.get("path"))
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Video.isSupported(ext: p.extension ?? "") else {
            throw MediaError.unsupportedFormat(p.extension ?? "")
        }
        guard !p.string.lowercased().contains("sample") else {
            throw MediaError.sampleMedia
        }

        try super.init(json: json)

        if downpour.type == .tv {
            guard let _ = downpour.season else {
                throw MediaError.Downpour.missingTVSeason(path.string)
            }
            guard let _ = downpour.episode else {
                throw MediaError.Downpour.missingTVEpisode(path.string)
            }
        }
    }

    override func move(to: Path, log: SwiftyBeaver.Type) throws -> Video {
        return try super.move(to: to, log: log) as! Video
    }

    override func convert(_ log: SwiftyBeaver.Type? = nil) throws -> Video {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable video (if necessary)
        return self
    }

    override class func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }

    override class func needsConversion(file: Path) -> Bool {
        return false
    }
}

/// Management for Audio files
final class Audio: BaseMedia {
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

    override func move(to: Path, log: SwiftyBeaver.Type) throws -> Audio {
        return try super.move(to: to, log: log) as! Audio
    }

    override func convert(_ log: SwiftyBeaver.Type? = nil) throws -> Audio {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable audio (if necessary)
        return self
    }

	override class func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }

    override class func needsConversion(file: Path) -> Bool {
        return false
    }
}

final class Subtitle: BaseMedia {
    enum SupportedExtension: String {
        case srt
        case smi
        case ssa
        case ass
        case vtt
    }

    /// Common subtitle languages to look out for
    private let commonLanguages: [String] = [
                                             "english", "spanish", "portuguese",
                                             "german", "swedish", "russian",
                                             "french", "chinese", "japanese",
                                             "hindu", "persian", "italian",
                                             "greek"
                                            ]

    override var plexFilename: String {
        var name = "\(plexName)."
        if let l = lang {
            name += "\(l)."
        }
        name += path.extension ?? "uft"
        return name
    }
    override var plexName: String {
        var name: String
        switch downpour.type {
            // If it's a movie file, plex wants "Title (YYYY)"
            case .movie:
                name = "\(downpour.title.wordCased)"
                if let year = downpour.year {
                    name += " (\(year))"
                }
            // If it's a tv show, plex wants "Title - sXXeYY"
            case .tv:
                name = "\(downpour.title.wordCased) - s\(String(format: "%02d", Int(downpour.season!)!))e\(String(format: "%02d", Int(downpour.episode!)!))"
            // Otherwise just return the title (shouldn't ever actually reach this)
            default:
                name = downpour.title.wordCased
        }
        var language: String?
        if let match = path.lastComponent.range(of: "anoXmous_([a-z]{3})", options: .regularExpression) {
            language = path.lastComponent[match].replacingOccurrences(of: "anoXmous_", with: "")
        } else {
            for lang in commonLanguages {
                if path.lastComponent.lowercased().contains(lang) || path.lastComponent.lowercased().contains(".\(lang.substring(to: 3)).") {
                    language = lang.substring(to: 3)
                    break
                }
            }
        }

        if let l = language {
            lang = l
        } else {
            lang = "unknown-\(path.lastComponent)"
        }

        // Return the calulated name
        return name
    }
    var lang: String?
    override var finalDirectory: Path {
        var name = plexName
        while name.contains("unknown") {
            name = Path(name).lastComponentWithoutExtension
        }
        var base: Path
        switch downpour.type {
        case .movie:
            base = Path("Movies\(Path.separator)\(plexName)")
        case .tv:
            base = Path("TV Shows\(Path.separator)\(downpour.title.wordCased)\(Path.separator)Season \(String(format: "%02d", Int(downpour.season!)!))\(Path.separator)\(plexName)")
        default:
            base = ""
        }
        return base
    }

    required init(_ path: Path) throws {
        try super.init(path)
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Subtitle.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(path.extension ?? "")
        }

        if downpour.type == .tv {
            guard let _ = downpour.season else {
                throw MediaError.Downpour.missingTVSeason(path.string)
            }
            guard let _ = downpour.episode else {
                throw MediaError.Downpour.missingTVEpisode(path.string)
            }
        }
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        let p = Path(try json.get("path"))
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Subtitle.isSupported(ext: p.extension ?? "") else {
            throw MediaError.unsupportedFormat(p.extension ?? "")
        }
        try super.init(json: json)

        if downpour.type == .tv {
            guard let _ = downpour.season else {
                throw MediaError.Downpour.missingTVSeason(p.string)
            }
            guard let _ = downpour.episode else {
                throw MediaError.Downpour.missingTVEpisode(p.string)
            }
        }
    }

    override func move(to: Path, log: SwiftyBeaver.Type) throws -> Subtitle {
        return try super.move(to: to, log: log) as! Subtitle
    }

    override func convert(_ log: SwiftyBeaver.Type? = nil) throws -> Subtitle {
        // Subtitles don't need to be converted
        return self
    }

    override class func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}

/// Management for media types that we don't care about and can just delete
final class Ignore: BaseMedia {
    enum SupportedExtension: String {
        case txt; case png; case jpg; case jpeg
        case gif; case rst; case md; case nfo
        case sfv; case sub; case idx; case css
        case js; case htm; case html; case url
        case php; case md5; case doc; case docx
        case rtf; case db
    }

    override var plexName: String {
        return path.lastComponentWithoutExtension
    }
    override var finalDirectory: Path {
        return "/dev/null"
    }

    required init(_ path: Path) throws {
        if !path.string.lowercased().contains("sample") && !path.string.lowercased().contains(".ds_store") {
            guard Ignore.isSupported(ext: path.extension ?? "") else {
                throw MediaError.unsupportedFormat(path.extension ?? "")
            }
        }
        try super.init(path)
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        let p = Path(try json.get("path"))
        if !p.string.lowercased().contains("sample") && !p.string.lowercased().contains(".ds_store") {
            guard Ignore.isSupported(ext: p.extension ?? "") else {
                throw MediaError.unsupportedFormat(p.extension ?? "")
            }
        }
        try super.init(json: json)
    }

    override func move(to: Path, log: SwiftyBeaver.Type) throws -> Ignore {
        log.verbose("Deleting ignorable file: \(path.string)")
        try path.delete()
        path = ""
        return self
    }

    override func convert(_ log: SwiftyBeaver.Type? = nil) throws -> Ignore {
        // Ignored files don't need to be converted
        return self
    }

	override class func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}
