/*

    Media.swift

    Created By: Jacob Williams
    Description: This file contains the media structures for easy management of downloaded files
    License: MIT License

*/

import Foundation
import PathKit
import Downpour

// Media related errors
enum MediaError: Swift.Error {
    case unsupportedFormat(String)
    case notImplemented
    case sampleMedia
    case alreadyExists(Path)
}

/// Protocol for the common implementation of Media types
protocol Media: class {
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
    func move(to newDirectory: Path) throws
    /// Converts the media file to a Plex DirectPlay supported format
    func convert() throws
    /// Returns whether of not the Media type supported the given format
    static func isSupported(ext: String) -> Bool
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

    func move(to plexPath: Path) throws {
        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory
        // Create the directory
        if !mediaDirectory.isDirectory {
            try mediaDirectory.mkpath()
        }

        // Create a path to the location where the file will RIP
        let finalRestingPlace = mediaDirectory + plexFilename

        // Ensure the finalRestingPlace doesn't already exist
        guard !finalRestingPlace.isFile else {
            throw MediaError.alreadyExists(finalRestingPlace)
        }
        
        // Move the file to the correct plex location
        try path.move(finalRestingPlace)
        // Change the path now to match
        path = finalRestingPlace
    }

    func convert() throws {
        throw MediaError.notImplemented
    }

    class func isSupported(ext: String) -> Bool {
        print("isSupported(ext: String) is not implemented!")
        return false
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
    }

    override func convert() throws {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable video (if necessary)
    }

    override static func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
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
        try super.init(path)
        guard Audio.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(path.extension ?? "")
        }
    }

    override func convert() throws {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable audio (if necessary)
    }

	override static func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
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
    }

    override func convert() throws {
        // Subtitles don't need to be converted
        return
    }

    override static func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}

/// Management for media types that we don't care about and can just delete
final class Ignore: BaseMedia {
    enum SupportedExtension: String {
        case txt; case png
        case jpg; case jpeg
        case gif; case rst
        case md; case nfo
        case sfv; case sub
        case idx; case css
        case js; case htm
        case html; case url
        case php; case md5
        case doc; case docx
        case rtf
    }

    override var plexName: String {
        return path.lastComponentWithoutExtension
    }
    override var finalDirectory: Path {
        return "/dev/null"
    }

    required init(_ path: Path) throws {
        if !path.string.lowercased().contains("sample") {
            guard Ignore.isSupported(ext: path.extension ?? "") else {
                throw MediaError.unsupportedFormat(path.extension ?? "")
            }
        }
        try super.init(path)
    }

    override func move(to plexPath: Path) throws {
        try path.delete()
    }

    override func convert() throws {
        // Ignored files don't need to be converted
        return
    }

	override static func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}
