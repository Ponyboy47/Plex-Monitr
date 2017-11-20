import Foundation

let indent = "\t\t"

enum FFProbeError: Error {
    enum JSONParserError: Error {
        case unknownCodec(String)
        case framerateIsNotDouble(String)
        case cannotCalculateFramerate(String)
    }
    enum DurationError: Error {
        case unknownDuration(String)
        case cannotConvertStringToUInt(type: String, string: String)
        case cannotConvertStringToDouble(type: String, string: String)
    }
    enum BitRateError: Error {
        case unableToConvertStringToDouble(String)
    }
    enum SampleRateError: Error {
        case unableToConvertStringToDouble(String)
    }
    enum IncorrectTypeError: Error {
        case video
        case audio
        case data
        case other(String)
    }
}

/// Struct for all of the streams returned by the `ffprobe` command
struct FFProbe: Decodable {
    fileprivate var streams: [FFProbeStreamProtocol] = []
    var videoStreams: [VideoStream] {
        return self.streams.filter({ $0.type == .video }) as! [VideoStream]
    }
    var audioStreams: [AudioStream] {
        return self.streams.filter({ $0.type == .audio }) as! [AudioStream]
    }
    var dataStreams: [DataStream] {
        return self.streams.filter({ $0.type == .data }) as! [DataStream]
    }
    var unknownStreams: [UnknownStream] {
        return self.streams.filter({ $0.type == .unknown }) as! [UnknownStream]
    }

    enum CodingKeys: String, CodingKey {
        case streams
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        streams = try values.decode([FFProbeStreamProtocol].self, forKey: .streams)
    }
}

enum CodecType: String, Codable {
    case video
    case audio
    case data
    case unknown
}

protocol Codec: Codable {}

enum VideoCodec: String, Codec {
    case h264
    case mpeg4
    case mjpeg
    case any
}
enum AudioCodec: String, Codec {
    case aac
    case ac3
    case eac3
    case mp3
    case any
}

protocol FFProbeStreamProtocol: Decodable {
    var index: Int { get set }
    var type: CodecType { get set }
    var duration: MediaDuration { get set }
    var bitRate: BitRate { get set }
    var tags: Tags? { get set }
    var language: Language? { get }
    var description: String { get }
}

extension FFProbeStreamProtocol {
    var language: Language? {
        return tags?.language ?? .und
    }
}

protocol FFProbeCodecStreamProtocol: FFProbeStreamProtocol {
    var rawCodec: String { get set }
    var codec: Codec { get set }
}

protocol FFProbeVideoStreamProtocol: FFProbeCodecStreamProtocol {
    var dimensions: (Int, Int) { get set }
    var aspectRatio: String { get set }
    var framerate: Double { get set }
    var bitDepth: Int? { get set }
}

protocol FFProbeAudioStreamProtocol: FFProbeCodecStreamProtocol {
    var sampleRate: SampleRate { get set }
    var channels: Int { get set }
    var channelLayout: ChannelLayout { get set }
}

struct UnknownStream: FFProbeStreamProtocol {
    var index: Int
    var type: CodecType = .unknown
    var duration: MediaDuration
    var bitRate: BitRate
    var tags: Tags?

    var description: String {
        var str = "\(indent)Index: \(index)"
        var bR = bitRate
        str += "\n\(indent)BitRate: \(bR.kbps) kb/s"
        str += "\n\(indent)Duration: \(duration.description)"
        if let l = language {
            str += "\n\(indent)Language: \(l)"
        }
        if let t = tags {
            str += "\n\(indent)Tags: \(t)"
        }

        return str
    }

    enum CodingKeys: String, CodingKey {
        case index
        case type = "codec_type"
        case duration
        case bitRate = "bit_rate"
        case tags
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        index = try values.decode(Int.self, forKey: .index)
        let t = try values.decodeIfPresent(CodecType.self, forKey: .type) ?? .unknown
        guard t == type else {
            switch t {
            case .video:
                throw FFProbeError.IncorrectTypeError.video
            case .audio:
                throw FFProbeError.IncorrectTypeError.audio
            case .data:
                throw FFProbeError.IncorrectTypeError.data
            default:
                throw FFProbeError.IncorrectTypeError.other(t.rawValue)
            }
        }
        duration = try values.decode(MediaDuration.self, forKey: .duration)

        bitRate = try values.decode(BitRate.self, forKey: .bitRate)

        tags = try values.decode(Tags.self, forKey: .tags)
    }
}

struct DataStream: FFProbeStreamProtocol {
    var index: Int
    var type: CodecType = .data
    var duration: MediaDuration
    var bitRate: BitRate
    var tags: Tags?

    var description: String {
        var str = "\(indent)Index: \(index)"
        var bR = bitRate
        str += "\n\(indent)BitRate: \(bR.kbps) kb/s"
        str += "\n\(indent)Duration: \(duration.description)"
        if let l = language {
            str += "\n\(indent)Language: \(l)"
        }
        if let t = tags {
            str += "\n\(indent)Tags: \(t)"
        }

        return str
    }

    enum CodingKeys: String, CodingKey {
        case index
        case type = "codec_type"
        case duration
        case bitRate = "bit_rate"
        case tags
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        index = try values.decode(Int.self, forKey: .index)
        let t = try values.decodeIfPresent(CodecType.self, forKey: .type) ?? .unknown
        guard t == type else {
            switch t {
            case .video:
                throw FFProbeError.IncorrectTypeError.video
            case .audio:
                throw FFProbeError.IncorrectTypeError.audio
            case .unknown:
                throw FFProbeError.IncorrectTypeError.other(t.rawValue)
            default:
                throw FFProbeError.IncorrectTypeError.data
            }
        }

        duration = try values.decode(MediaDuration.self, forKey: .duration)

        bitRate = try values.decode(BitRate.self, forKey: .bitRate)

        tags = try values.decode(Tags.self, forKey: .tags)
    }
}

struct VideoStream: FFProbeVideoStreamProtocol {
    var index: Int
    var rawCodec: String
    var type: CodecType = .video
    var codec: Codec
    var duration: MediaDuration
    var bitRate: BitRate
    var tags: Tags?
    var dimensions: (Int, Int)
    var aspectRatio: String
    var framerate: Double
    var bitDepth: Int?

    var description: String {
        var str = "\(indent)Index: \(index)"
        str += "\n\(indent)Type: \(type)"
        str += "\n\(indent)Codec: \(codec)"
        var bR = bitRate
        str += "\n\(indent)BitRate: \(bR.kbps) kb/s"
        str += "\n\(indent)Duration: \(duration.description)"
        str += "\n\(indent)Dimensions: \(dimensions.0)x\(dimensions.1)"
        str += "\n\(indent)Aspect Ratio: \(aspectRatio)"
        str += "\n\(indent)Framerate: \(framerate) fps"
        if let b = bitDepth {
            str += "\n\(indent)Bit Depth: \(b)"
        }
        if let l = language {
            str += "\n\(indent)Language: \(l)"
        }
        if let t = tags {
            str += "\n\(indent)Tags: \(t)"
        }

        return str
    }

    enum CodingKeys: String, CodingKey {
        case index
        case rawCodec = "codec_name"
        case type = "codec_type"
        case duration
        case bitRate = "bit_rate"
        case tags
        case width
        case height
        case aspectRatio = "display_aspect_ratio"
        case framerate = "avg_frame_rate"
        case bitDepth = "bits_per_raw_sample"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        index = try values.decode(Int.self, forKey: .index)
        rawCodec = try values.decode(String.self, forKey: .rawCodec)

        let t = try values.decodeIfPresent(CodecType.self, forKey: .type) ?? .unknown
        guard t == type else {
            switch t {
            case .unknown:
                throw FFProbeError.IncorrectTypeError.other(rawCodec)
            case .data:
                throw FFProbeError.IncorrectTypeError.data
            case .audio:
                throw FFProbeError.IncorrectTypeError.audio
            default:
                throw FFProbeError.IncorrectTypeError.video
            }
        }

        guard let c = try? values.decode(VideoCodec.self, forKey: .rawCodec) else {
            throw FFProbeError.JSONParserError.unknownCodec(rawCodec)
        }
        codec = c

        duration = try values.decode(MediaDuration.self, forKey: .duration)

        bitRate = try values.decode(BitRate.self, forKey: .bitRate)

        tags = try values.decode(Tags.self, forKey: .tags)

        let width = try values.decode(Int.self, forKey: .width)
        let height = try values.decode(Int.self, forKey: .height)
        dimensions = (width, height)

        aspectRatio = try values.decode(String.self, forKey: .aspectRatio)

        let framerateString = try values.decode(String.self, forKey: .framerate)
        if framerateString.contains("/") {
            let components = framerateString.components(separatedBy: "/")
            guard let top = Double(components[0]), let bottom = Double(components[1]) else {
                throw FFProbeError.JSONParserError.cannotCalculateFramerate(framerateString)
            }
            var f = top / bottom
            if f < 0 {
                f = 0
            }
            framerate = f
        } else {
            guard var f = Double(framerateString) else {
                throw FFProbeError.JSONParserError.framerateIsNotDouble(framerateString)
            }
            if f < 0 {
                f = 0
            }
            framerate = f
        }

        bitDepth = try values.decode(Int.self, forKey: .bitDepth)
    }
}

struct AudioStream: FFProbeAudioStreamProtocol {
    var index: Int
    var rawCodec: String
    var type: CodecType = .audio
    var codec: Codec
    var duration: MediaDuration
    var bitRate: BitRate
    var tags: Tags?
    var sampleRate: SampleRate
    var channels: Int
    var channelLayout: ChannelLayout

    var description: String {
        var str = "\(indent)Index: \(index)"
        str += "\n\(indent)Type: \(type)"
        str += "\n\(indent)Codec: \(codec)"
        var bR = bitRate
        str += "\n\(indent)BitRate: \(bR.kbps) kb/s"
        str += "\n\(indent)Duration: \(duration.description)"
        var sR = sampleRate
        str += "\n\(indent)Sample Rate: \(sR.khz) kHz"
        str += "\n\(indent)Channels: \(channels)"
        str += "\n\(indent)Layout: \(channelLayout)"
        if let l = language {
            str += "\n\(indent)Language: \(l)"
        }
        if let t = tags {
            str += "\n\(indent)Tags: \(t)"
        }

        return str
    }

    enum CodingKeys: String, CodingKey {
        case index
        case rawCodec = "codec_name"
        case type = "codec_type"
        case duration
        case bitRate = "bit_rate"
        case tags
        case sampleRate = "sample_rate"
        case channels
        case channelLayout = "channel_layout"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        index = try values.decode(Int.self, forKey: .index)
        rawCodec = try values.decode(String.self, forKey: .rawCodec)

        let t = try values.decodeIfPresent(CodecType.self, forKey: .type) ?? .unknown
        guard t == type else {
            switch t {
            case .unknown:
                throw FFProbeError.IncorrectTypeError.other(rawCodec)
            case .video:
                throw FFProbeError.IncorrectTypeError.video
            case .data:
                throw FFProbeError.IncorrectTypeError.data
            default:
                throw FFProbeError.IncorrectTypeError.audio
            }
        }
        guard let c = try? values.decode(AudioCodec.self, forKey: .rawCodec) else {
            throw FFProbeError.JSONParserError.unknownCodec(rawCodec)
        }
        codec = c

        duration = try values.decode(MediaDuration.self, forKey: .duration)

        bitRate = try values.decode(BitRate.self, forKey: .bitRate)

        tags = try values.decode(Tags.self, forKey: .tags)

        sampleRate = try values.decode(SampleRate.self, forKey: .sampleRate)

        channels = try values.decode(Int.self, forKey: .channels)

        channelLayout = try values.decodeIfPresent(ChannelLayout.self, forKey: .channelLayout) ?? .unknown_or_new
    }
}

protocol Container: Codable {}

enum VideoContainer: String, Container {
    case mp4
    case m4v
    case mkv
    case other
}

enum AudioContainer: String, Container {
    case aac
    case ac3
    case mp3
    case other
}

enum ChannelLayout: String, Codable {
    case mono
    case stereo
    case unknown_or_new
}

struct MediaDuration: Codable {
    var hours: UInt
    var minutes: UInt
    var seconds: UInt
    var description: String {
        var d = ""
        if hours > 0 {
            d += "\(hours):"
        }

        if hours > 0 || minutes > 0 {
            d += String(format: "%02d:", minutes)
        }

        d += String(format: "%02d", seconds)
        return d
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let durationString = try container.decode(String.self)
        let parts = durationString.components(separatedBy: ":")

        if parts.count == 3 {
            guard let h = UInt(parts[0]) else {
                throw FFProbeError.DurationError.cannotConvertStringToUInt(type: "hours", string: parts[0])
            }
            hours = h
            guard let m = UInt(parts[1]) else {
                throw FFProbeError.DurationError.cannotConvertStringToUInt(type: "minutes", string: parts[1])
            }
            minutes = m
            let splitSeconds = parts[2].components(separatedBy: ".")
            guard let s = UInt(splitSeconds[0]) else {
                throw FFProbeError.DurationError.cannotConvertStringToUInt(type: "seconds", string: splitSeconds[0])
            }
            seconds = s
        } else if parts.count == 2 {
            hours = 0
            guard let m = UInt(parts[0]) else {
                throw FFProbeError.DurationError.cannotConvertStringToUInt(type: "minutes", string: parts[0])
            }
            minutes = m
            let splitSeconds = parts[1].components(separatedBy: ".")
            guard let s = UInt(splitSeconds[0]) else {
                throw FFProbeError.DurationError.cannotConvertStringToUInt(type: "seconds", string: splitSeconds[0])
            }
            seconds = s
        } else if parts.count == 1 {
            guard let d = Double(durationString) else {
                throw FFProbeError.DurationError.cannotConvertStringToDouble(type: "seconds", string: durationString)
            }
            seconds = UInt(d)
            minutes = 0
            hours = 0
            while seconds >= 60 {
                minutes += 1
                if minutes == 60 {
                    hours += 1
                    minutes = 0
                }
                seconds -= 60
            }
        } else {
            throw FFProbeError.DurationError.unknownDuration(durationString)
        }
    }

     init(double duration: Double) {
         hours = 0
         minutes = 0
         seconds = UInt(duration)
         while seconds >= 60 {
             seconds -= 60
             minutes += 1
             if minutes >= 60 {
                 minutes -= 60
                 hours += 1
             }
         }
     }
}

extension MediaDuration: Comparable {
    static func ==(lhs: MediaDuration, rhs: MediaDuration) -> Bool {
        return lhs.hours == rhs.hours && lhs.minutes == rhs.minutes && lhs.seconds == rhs.seconds
    }

    static func <(lhs: MediaDuration, rhs: MediaDuration) -> Bool {
        if lhs.hours < rhs.hours {
            return true
        } else if lhs.hours == rhs.hours && lhs.minutes < rhs.minutes {
            return true
        } else if lhs.hours == rhs.hours && lhs.minutes == rhs.minutes && lhs.seconds < rhs.seconds {
            return true
        } else {
            return false
        }
    }
}

struct BitRate: Decodable {
    enum BitRateUnit: String {
        case bps
        case kbps
        case mbps
    }
    private var value: Double
    private var unit: BitRateUnit
    lazy var bps: Double = {
        switch self.unit {
        case .bps:
            return self.value
        case .kbps:
            return self.value * 1000.0
        case .mbps:
            return self.value * 1000.0 * 1000.0
        }
    }()
    lazy var kbps: Double = {
        switch self.unit {
        case .bps:
            return self.value / 1000.0
        case .kbps:
            return self.value
        case .mbps:
            return self.value * 1000.0
        }
    }()
    lazy var mbps: Double = {
        switch self.unit {
        case .bps:
            return self.value / 1000.0 / 1000.0
        case .kbps:
            return self.value / 1000.0
        case .mbps:
            return self.value
        }
    }()

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let bitRateString = try container.decode(String.self)

        if bitRateString.hasSuffix("Mbit/s") {
            unit = .mbps
            guard let v = Double(bitRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.BitRateError.unableToConvertStringToDouble(bitRateString.components(separatedBy: " ")[0])
            }
            value = v
        } else if bitRateString.hasSuffix("Kbit/s") {
            unit = .kbps
            guard let v = Double(bitRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.BitRateError.unableToConvertStringToDouble(bitRateString.components(separatedBy: " ")[0])
            }
            value = v
        } else {
            unit = .bps
            guard let v = Double(bitRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.BitRateError.unableToConvertStringToDouble(bitRateString.components(separatedBy: " ")[0])
            }
            value = v
        }
    }
}

extension BitRate: Comparable {
    static func ==(lhs: BitRate, rhs: BitRate) -> Bool {
        var l = lhs
        var r = rhs
        return l.bps == r.bps
    }

    static func <(lhs: BitRate, rhs: BitRate) -> Bool {
        var l = lhs
        var r = rhs
        return l.bps < r.bps
    }
}

struct SampleRate: Decodable {
    enum SampleRateUnit: String {
        case hz
        case khz
        case mhz
    }
    private var value: Double
    private var unit: SampleRateUnit
    lazy var hz: Double = {
        switch self.unit {
        case .hz:
            return self.value
        case .khz:
            return self.value * 1000.0
        case .mhz:
            return self.value * 1000.0 * 1000.0
        }
    }()
    lazy var khz: Double = {
        switch self.unit {
        case .hz:
            return self.value / 1000.0
        case .khz:
            return self.value
        case .mhz:
            return self.value * 1000.0
        }
    }()
    lazy var mhz: Double = {
        switch self.unit {
        case .hz:
            return self.value / 1000.0 / 1000.0
        case .khz:
            return self.value / 1000.0
        case .mhz:
            return self.value
        }
    }()

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let sampleRateString = try container.decode(String.self)

        if sampleRateString.hasSuffix("mHz") {
            unit = .mhz
            guard let v = Double(sampleRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.SampleRateError.unableToConvertStringToDouble(sampleRateString.components(separatedBy: " ")[0])
            }
            value = v
        } else if sampleRateString.hasSuffix("kHz") {
            unit = .khz
            guard let v = Double(sampleRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.SampleRateError.unableToConvertStringToDouble(sampleRateString.components(separatedBy: " ")[0])
            }
            value = v
        } else {
            unit = .hz
            guard let v = Double(sampleRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.SampleRateError.unableToConvertStringToDouble(sampleRateString.components(separatedBy: " ")[0])
            }
            value = v
        }
    }
}

extension SampleRate: Comparable {
    static func ==(lhs: SampleRate, rhs: SampleRate) -> Bool {
        var l = lhs
        var r = rhs
        return l.hz == r.hz
    }

    static func <(lhs: SampleRate, rhs: SampleRate) -> Bool {
        var l = lhs
        var r = rhs
        return l.hz < r.hz
    }
}

enum Language: String, Codable {
    case eng // English
    case spa // Spanish
    case ita // Italian
    case fre // French
    case ger // German
    case por // Portuguese
    case dut // Dutch
    case jap // Japanese
    case chi // Chinese
    case rus // Russian
    case per // Persian
    case und // Undetermined
}

struct Tags: Codable {
    var language: Language?
}
