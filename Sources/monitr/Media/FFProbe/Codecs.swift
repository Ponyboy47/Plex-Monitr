protocol Codec: Codable {}

enum VideoCodec: String, Codec {
    case h264
    case mpeg4
    case mjpeg
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

    init?(rawValue: String?) throws {
        if let rV = rawValue {
            self.init(rawValue: rV)
        } else {
            return nil
        }
    }
    case any
}
enum SubtitleCodec: String, Codec {
    case srt
    case mov_text

    init?(rawValue: String?) throws {
        if let rV = rawValue {
            self.init(rawValue: rV)
        } else {
            return nil
        }
    }
    case any
}
