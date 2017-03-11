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
    case unsupportedFormat(format: String)
    case notImplemented
}

/// Protocol for the common implementation of Media types
protocol Media: class {
    /// The path to the media file
    var path: Path { get set }
    /// Used to retrieve basic data from the file
    var downpour: Downpour { get set }

    // These are gets so that they can be lazy vars in the protocol implementations

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
        return self.downpour.title
    }
    var plexFilename: String {
        // Return the plexified name + it's extension
        return self.plexName + "." + (self.path.extension ?? "")
    }
    var finalDirectory: Path {
        print("finalDirectory not implemented!")
        return ""
    }

    required init(_ path: Path) throws {
        // Set the media file's path to the absolute path
        self.path = path.absolute
        // Create the downpour object
        self.downpour = Downpour(fullPath: path)
    }

    func move(to plexPath: Path) throws {
        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory
        // Preemptively try and create the directory
        try mediaDirectory.mkpath()
        // Create a path to the location where the file will RIP
        let finalRestingPlace = mediaDirectory + plexFilename
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
class Video: BaseMedia {
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
        switch self.downpour.type {
            // If it's a movie file, plex wants "Title (YYYY)"
            case .movie:
                name = "\(self.downpour.title)"
                if let year = self.downpour.year {
                    name += " (\(year))"
                }
            // If it's a tv show, plex wants "Title - sXXeYY"
            case .tv:
                name = "\(self.downpour.title) - s\(self.downpour.season!)e\(self.downpour.episode!)"
            // Otherwise just return the title (shouldn't ever actually reach this)
            default:
                name = self.downpour.title
        }
        // Return the calulated name
        return name
    }
    override var finalDirectory: Path {
        var base: Path
        switch self.downpour.type {
        case .movie:
            base = Path("Movies\(Path.separator)\(self.plexName)")
        case .tv:
            base = Path("TV Shows\(Path.separator)\(self.downpour.title)\(Path.separator)Season \(self.downpour.season!)")
        default:
            base = ""
        }
        return base
    }

    required init(_ path: Path) throws {
        try super.init(path)
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Video.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(format: path.extension ?? "")
        }
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
class Audio: BaseMedia {
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
        return self.path.lastComponentWithoutExtension
    }
    override var finalDirectory: Path {
        // Music goes in the Music + Artist + Album directory
        var base: Path = "Music"
        guard let artist = self.downpour.artist else { return base + "Unknown" }
        base += artist
        guard let album = self.downpour.album else { return base + "Unknown" }
        base += album
        return base
    }

    required init(_ path: Path) throws {
        try super.init(path)
        guard Audio.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(format: path.extension ?? "")
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

class Subtitle: BaseMedia {
    enum SupportedExtension: String {
        case srt
        case smi
        case ssa
        case ass
        case vtt
    }

    // Lazy vars so these are calculated only once

    override var plexName: String {
        var name: String
        switch self.downpour.type {
            // If it's a movie file, plex wants "Title (YYYY)"
            case .movie:
                name = "\(self.downpour.title)"
                if let year = self.downpour.year {
                    name += " (\(year))"
                }
            // If it's a tv show, plex wants "Title - sXXeYY"
            case .tv:
                name = "\(self.downpour.title) - s\(self.downpour.season!)e\(self.downpour.episode!)"
            // Otherwise just return the title (shouldn't ever actually reach this)
            default:
                name = self.downpour.title
        }
        // Return the calulated name
        return name
    }
    override var finalDirectory: Path {
        var base: Path
        switch self.downpour.type {
        case .movie:
            base = Path("Movies\(Path.separator)\(self.plexName)")
        case .tv:
            base = Path("TV Shows\(Path.separator)\(self.downpour.title)\(Path.separator)Season \(self.downpour.season!)")
        default:
            base = ""
        }
        return base
    }

    required init(_ path: Path) throws {
        try super.init(path)
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Subtitle.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(format: path.extension ?? "")
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
class Ignore: BaseMedia {
    enum SupportedExtension: String {
        case txt
        case png
        case jpg
        case jpeg
        case gif
        case rst
        case md
        case nfo
        case sfv
    }

    override var plexName: String {
        return self.path.lastComponentWithoutExtension
    }
    override var plexFilename: String {
        return self.plexName + (self.path.extension ?? "")
    }
    override var finalDirectory: Path {
        return "/dev/null"
    }

    required init(_ path: Path) throws {
        try super.init(path)
        guard Ignore.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(format: path.extension ?? "")
        }
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
