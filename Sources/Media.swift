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
}

/// Protocol for the common implementation of Media types
protocol Media {
    /// The path to the media file
    var path: Path { get set }
    /// Used to retrieve basic data from the file
    var downpour: Downpour { get set }

    // These are mutating gets so that they can be lazy vars in the protocol implementations

    /// The name of the file in the proper Plex standardized format
    var plexName: String { mutating get }
    /// The plex filename (including it's extension)
    var plexFilename: String { mutating get }
    /// The directory where the media should be placed within plex
    var finalDirectory: Path { mutating get }

    /// Initializer
    init(_ path: Path) throws
    /// Moves the media file to the finalDirectory
    mutating func move(to newDirectory: Path) throws
    /// Converts the media file to a Plex DirectPlay supported format
    mutating func convert() throws
    /// Returns whether of not the Media type supported the given format
    static func isSupported(ext: String) -> Bool
}

/// Management for Video files
struct Video: Media {
    /// The supported extensions
    enum SupportedExtension: String {
        case mp4
        case mkv
        case m4v
        case avi
        case wmv
    }

    var path: Path
    var downpour: Downpour

    // Lazy vars so these are calculated only once

    lazy var plexName: String = {
        var name: String
        switch self.downpour.type {
            // If it's a movie file, plex wants "Title (YYYY)"
            case .movie:
                name = "\(self.downpour.title) (\(self.downpour.year))"
            // If it's a tv show, plex wants "Title - sXXeYY"
            case .tv:
                name = "\(self.downpour.title) - s\(self.downpour.season)e\(self.downpour.episode)"
            // Otherwise just return the title (shouldn't ever actually reach this)
            default:
                name = self.downpour.title
        }
        // Return the calulated name
        return name
    }()
    lazy var plexFilename: String = {
        // Return the plexified name + it's extension
        return self.plexName + (self.path.extension ?? "")
    }()
    lazy var finalDirectory: Path = {
        // The base is either 'Movies' or 'TV Shows'
        var base: Path = self.downpour.type == .movie ? "Movies" : "TV Shows"
        // If it's a movie, just use the plexName. If it's a tv show, use the show title/Season ##
        base += self.downpour.type == .movie ? self.plexName : "\(self.downpour.title)/Season \(self.downpour.season)"
        // The final directory is set so that multiple versions of videos can easily be incorporated
        return base
    }()

    init(_ path: Path) throws {
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Video.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(format: path.extension ?? "")
        }
        // Set the media file's path to the absolute path
        self.path = path.absolute
        // Create the downpour object
        self.downpour = Downpour(fullPath: path)
    }

    mutating func move(to plexPath: Path) throws {
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

    mutating func convert() throws {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable video (if necessary)
    }

    static func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}

/// Management for Audio files
struct Audio: Media {
    /// The supported extensions
    enum SupportedExtension: String {
        case mp3
        case m4a
        case alac
        case flac
        case aac
        case wav
    }

    var path: Path
    var downpour: Downpour

    lazy var plexName: String = {
        // Audio files are usually pretty simple
        return self.path.lastComponentWithoutExtension
    }()
    lazy var plexFilename: String = {
        // This pretty much never changes
        return self.plexName + (self.path.extension ?? "")
    }()
    lazy var finalDirectory: Path = {
        // Music goes in the Music + Artist + Album directory
        var base: Path = "Music"
        guard let artist = self.downpour.artist else { return base + "Unknown" }
        base += artist
        guard let album = self.downpour.album else { return base + "Unknown" }
        base += album
        return base
    }()

    init(_ path: Path) throws {
        guard Audio.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(format: path.extension ?? "")
        }
        self.path = path.absolute
        self.downpour = Downpour(fullPath: path)
    }

    mutating func move(to plexPath: Path) throws {
        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory
        // Preemptively try and create the directory
        try mediaDirectory.mkpath()
        // Create a path to the location where the file wil RIP
        let finalRestingPlace = mediaDirectory + plexFilename
        // Move the file to the correct plex location
        try path.move(finalRestingPlace)
        // Change the path now to match it's final resting place
        path = finalRestingPlace
    }

    mutating func convert() throws {
        // Use the Handbrake CLI to convert to Plex DirectPlay capable audio (if necessary)
    }

	static func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}

struct Subtitle: Media {
    enum SupportedExtension: String {
        case srt
        case smi
        case ssa
        case ass
        case vtt
    }

    var path: Path
    var downpour: Downpour

    lazy var plexName: String = {
		var name: String
        switch self.downpour.type {
            // If it's a movie file, plex wants "Title (YYYY)"
            case .movie:
                name = "\(self.downpour.title) (\(self.downpour.year))"
            // If it's a tv show, plex wants "Title - sXXeYY"
            case .tv:
                name = "\(self.downpour.title) - s\(self.downpour.season)e\(self.downpour.episode)"
            // Otherwise just return the title (shouldn't ever actually reach this)
            default:
                name = self.downpour.title
        }
        // Return the calulated name
        return name
    }()
    lazy var plexFilename: String = {
        // This really does never change
        return self.plexName + (self.path.extension ?? "")
    }()
    lazy var finalDirectory: Path = {
		// The base is either 'Movies' or 'TV Shows'
          var base: Path = self.downpour.type == .movie ? "Movies" : "TV Shows"
          // If it's a movie, just use the plexName. If it's a tv show, use the show title/Season ##
          base += self.downpour.type == .movie ? self.plexName : "\(self.downpour.title)/Season \(self.downpour.season)"
          // The final directory is set so that multiple versions of videos can easily be incorporated
          return base
    }()

    init(_ path: Path) throws {
        guard Subtitle.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(format: path.extension ?? "")
        }
        self.path = path.absolute
        self.downpour = Downpour(fullPath: path)
    }

    mutating func move(to plexPath: Path) throws {
        // Get the location of the finalDirectory inside the plexPath
        let mediaDirectory = plexPath + finalDirectory
        // Preemptively try and create the directory
        try mediaDirectory.mkpath()
        // Create a path to the location where the file wil RIP
        let finalRestingPlace = mediaDirectory + plexFilename
        // Move the file to the correct plex location
        try path.move(finalRestingPlace)
        // Change the path now to match it's final resting place
        path = finalRestingPlace
    }

    mutating func convert() throws {
        // Subtitles can't/don't need to be converted
        return
    }

	static func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}

/// Management for media types that we don't care about and can just delete
struct Ignore: Media {
    enum SupportedExtension: String {
        case txt
        case png
        case jpg
        case jpeg
        case gif
        case rst
        case md
    }

    var path: Path
    var downpour: Downpour

    lazy var plexName: String = {
        return self.path.lastComponentWithoutExtension
    }()
    lazy var plexFilename: String = {
        return self.plexName + (self.path.extension ?? "")
    }()
    lazy var finalDirectory: Path = {
        return "/dev/null"
    }()

    init(_ path: Path) throws {
        guard Ignore.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(format: path.extension ?? "")
        }
        self.path = path.absolute
        self.downpour = Downpour(fullPath: path)
    }

    mutating func move(to plexPath: Path) throws {
        try path.delete()
    }

    mutating func convert() throws {
        // Ignored files don't need to be converted
        return
    }

	static func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}
