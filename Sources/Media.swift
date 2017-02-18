import Foundation
import PathKit
import Downpour

enum MediaError: Swift.Error {
    case unsupportedFormat
}

protocol MediaFile {
    associatedtype MediaType
    associatedtype MediaFormat

    var path: Path { get set }
    var name: String { get }
    var format: MediaFormat { get set }

    init(_ path: Path) throws
}

enum VideoFormat: String {
    case mp4
    case mkv
    case m4v
    case avi
    case wmv
}

struct Video: MediaFile {
    typealias MediaType = Video
    typealias MediaFormat = VideoFormat

    private var dp: Downpour

    var path: Path
    var name: String {
        return dp.title
    }
    var format: MediaFormat
    var type: DownpourType {
        return dp.type
    }
    init(_ path: Path) throws {
        self.path = path
        guard let f = VideoFormat(rawValue: path.extension ?? "") else {
            throw MediaError.unsupportedFormat
        }
        self.format = f
        self.dp = Downpour(string: path.lastComponentWithoutExtension)
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

struct Audio: MediaFile {
    typealias MediaType = Audio
    typealias MediaFormat = AudioFormat
    var path: Path
    var name: String {
        return path.lastComponentWithoutExtension
    }
    var format: MediaFormat
    init(_ path: Path) throws {
        self.path = path
        guard let f = AudioFormat(rawValue: path.extension ?? "") else {
            throw MediaError.unsupportedFormat
        }
        self.format = f
    }
}
