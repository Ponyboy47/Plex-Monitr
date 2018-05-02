// swiftlint:disable identifier_name

protocol Codec: Codable {}

enum VideoCodec: String, Codec {
    case h264
    case mpeg4
    case mjpeg
    case mpeg2video
    case vc1
    case msmpeg4v2
    case any

    init?(rawValue: String?) throws {
        if let rV = rawValue {
            self.init(rawValue: rV)
        } else {
            return nil
        }
    }
}
enum AudioCodec: String, Codec {
    case aac
    case ac3
    case eac3
    case mp3
    case truehd
    case dca
    case any

    init?(rawValue: String?) throws {
        if let rV = rawValue {
            self.init(rawValue: rV)
        } else {
            return nil
        }
    }
}
enum SubtitleCodec: String, Codec {
    case srt
    case mov_text
    case dvdsub
    case pgssub
    case any

    init?(rawValue: String?) throws {
        if let rV = rawValue {
            self.init(rawValue: rV)
        } else {
            return nil
        }
    }
}
