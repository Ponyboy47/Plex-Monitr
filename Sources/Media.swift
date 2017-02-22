import Foundation
import PathKit
import Downpour

enum MediaError: Swift.Error {
    case unsupportedFormat
}

protocol Media {
    var path: Path { get set }
    var name: String { get }
    var filename: String { get }

    init(_ path: Path) throws
    func move(to newDirectory: Path) throws
}

enum VideoFormat: String {
    case mp4
    case mkv
    case m4v
    case avi
    case wmv
}

struct Video: Media {
    private var downpour: Downpour

    var path: Path
    var name: String {
        var filename: String
        switch downpour.type {
            case .movie:
                filename = "\(downpour.title) (\(downpour.year))"
            case .tv:
                filename = "\(downpour.title) - s\(downpour.season)e\(downpour.episode)"
        }
        return filename
    }
    var filename: String {
        return name + (path.extension ?? "")
    }
    private var directory: Path {
        var base: Path = downpour.type == .movie ? "Movies" : "TV Shows"
        base += downpour.type == .movie ? name : "\(downpour.title)/Season \(downpour.season)"
        return base
    }

    init(_ path: Path) throws {
        self.path = path.absolute
        guard let _ = VideoFormat(rawValue: path.extension ?? "") else {
            throw MediaError.unsupportedFormat
        }
        self.downpour = Downpour(string: path.lastComponentWithoutExtension)
    }

    func move(to plexPath: Path) throws {
        let mediaDirectory = plexPath + directory
        try mediaDirectory.mkpath()
        try path.move(mediaDirectory + filename)
    }
}

enum AudioFormat: String {
    case mp3
    case m4a
    case alac
    case flac
    case aac
    case wav
}

struct Audio: Media {
    var path: Path
    var name: String {
        return path.lastComponentWithoutExtension
    }
    var filename: String {
        return name + (path.extension ?? "")
    }

    init(_ path: Path) throws {
        self.path = path.absolute
        guard let _ = AudioFormat(rawValue: path.extension ?? "") else {
            throw MediaError.unsupportedFormat
        }
    }

    func move(to plexPath: Path) throws {
    }
}
