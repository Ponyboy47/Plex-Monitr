import JSON

enum FFProbeError: Error {
    enum JSONParserError: Error {
        case unknownCodecType
        case framerateIsNotDouble(String)
        case cannotCalculateFramerate(String)
    }
    enum DurationError: Error {
        case unknownDuration(String)
        case cannotConvertStringToUInt(type: String, string: String)
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

struct FFProbe {
    fileprivate var streams: [FFProbeStreamProtocol] = []
    lazy var videoStreams: [VideoStream] = {
        return self.streams.filter({ $0.type == .video }) as! [VideoStream]
    }()
    lazy var audioStreams: [AudioStream] = {
        return self.streams.filter({ $0.type == .audio }) as! [AudioStream]
    }()
    lazy var dataStreams: [DataStream] = {
        return self.streams.filter({ $0.type == .data }) as! [DataStream]
    }()
    lazy var unknownStreams: [UnknownStream] = {
        return self.streams.filter({ $0.type == .unknown }) as! [UnknownStream]
    }()
    init() {}
}

extension FFProbe: JSONInitializable {
    init(_ ffprobeString: String) throws {
        try self.init(json: JSON.Parser.parse(ffprobeString))
    }

    init(json: JSON) throws {
        let genericStreams = try json.get(field: "streams")
        for stream in genericStreams {
            do {
                let s = try UnknownStream(json: stream)
                streams.append(s)
            } catch FFProbeError.IncorrectTypeError.data {
                let s = try DataStream(json: stream)
                streams.append(s)
            } catch FFProbeError.IncorrectTypeError.video {
                let s = try VideoStream(json: stream)
                streams.append(s)
            } catch FFProbeError.IncorrectTypeError.audio {
                let s = try AudioStream(json: stream)
                streams.append(s)
            }
        }
    }
}

enum CodecType: String {
    case video
    case audio
    case data
    case unknown
}

protocol Codec {}

enum VideoCodec: String, Codec {
    case h264
    case mpeg4
    case any
}
enum AudioCodec: String, Codec {
    case aac
    case ac3
    case eac3
    case mp3
    case any
}
enum UnknownCodec: Codec {
    case unknown_or_new(String)
}

protocol FFProbeStreamProtocol: JSONInitializable {
    var index: Int { get set }
    var type: CodecType { get set }
    var duration: MediaDuration { get set }
    var bitRate: BitRate { get set }
    var tags: Tags? { get set }
    var language: Language? { get set }
    var description: String { get }
    init(stream str: String) throws
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
    var language: Language?

    var description: String {
        let indent = "\t\t"
        var str = "\(indent)Index: \(index)"
        var bR = bitRate
        str += "\n\(indent)BitRate: \(bR.kbps) kb/s"
        str += "\n\(indent)Duration: \(duration.description)"
        if let l = language {
            str += "\n\(indent)Language: \(l.rawValue)"
        }
        if let t = tags {
            str += "\n\(indent)Tags: \(t)"
        }

        return str
    }

    init(stream str: String) throws {
        try self.init(json: JSON.Parser.parse(str))
    }

    init(json: JSON) throws {
        index = try json.get("index")
        let t: CodecType = try CodecType(rawValue: json.get("codec_type")) ?? .unknown
        guard t == self.type else {
            switch t {
            case .video:
                throw FFProbeError.IncorrectTypeError.video
            case .audio:
                throw FFProbeError.IncorrectTypeError.audio
            case .data:
                throw FFProbeError.IncorrectTypeError.data
            default:
                throw FFProbeError.IncorrectTypeError.other(try json.get("codec_type"))
            }
        }

        let durationString: String = try json.get("duration")
        duration = try MediaDuration(durationString)

        let bitRateString: String = try json.get("bit_rate")
        bitRate = try BitRate(bitRateString)

        tags = try? json.get("tags")

        language = tags?.language ?? .und
    }
}

struct DataStream: FFProbeStreamProtocol {
    var index: Int
    var type: CodecType = .data
    var duration: MediaDuration
    var bitRate: BitRate
    var tags: Tags?
    var language: Language?

    var description: String {
        let indent = "\t\t"
        var str = "\(indent)Index: \(index)"
        var bR = bitRate
        str += "\n\(indent)BitRate: \(bR.kbps) kb/s"
        str += "\n\(indent)Duration: \(duration.description)"
        if let l = language {
            str += "\n\(indent)Language: \(l.rawValue)"
        }
        if let t = tags {
            str += "\n\(indent)Tags: \(t)"
        }

        return str
    }

    init(stream str: String) throws {
        try self.init(json: JSON.Parser.parse(str))
    }

    init(json: JSON) throws {
        index = try json.get("index")
        let t: CodecType = try CodecType(rawValue: json.get("codec_type")) ?? .unknown
        guard t == self.type else {
            switch t {
            case .video:
                throw FFProbeError.IncorrectTypeError.video
            case .audio:
                throw FFProbeError.IncorrectTypeError.audio
            case .unknown:
                throw FFProbeError.IncorrectTypeError.other(try json.get("codec_type"))
            default:
                throw FFProbeError.IncorrectTypeError.data
            }
        }

        let durationString: String = try json.get("duration")
        duration = try MediaDuration(durationString)

        let bitRateString: String = try json.get("bit_rate")
        bitRate = try BitRate(bitRateString)

        tags = try? json.get("tags")

        language = tags?.language ?? .und
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
    var language: Language?
    var dimensions: (Int, Int)
    var aspectRatio: String
    var framerate: Double
    var bitDepth: Int?

    var description: String {
        return ""
    }

    init(stream str: String) throws {
        try self.init(json: JSON.Parser.parse(str))
    }

    init(json: JSON) throws {
        index = try json.get("index")
        rawCodec = try json.get("codec_name")
        let t: CodecType = try CodecType(rawValue: json.get("codec_type")) ?? .unknown
        guard t == self.type else {
            switch t {
            case .unknown:
                throw FFProbeError.IncorrectTypeError.other(try json.get("codec_type"))
            case .data:
                throw FFProbeError.IncorrectTypeError.data
            case .audio:
                throw FFProbeError.IncorrectTypeError.audio
            default:
                throw FFProbeError.IncorrectTypeError.video
            }
        }
        codec = try VideoCodec(rawValue: json.get("codec_name")) ?? UnknownCodec.unknown_or_new(json.get("codec_name"))

        duration = try MediaDuration(json.get("duration"))

        bitRate = try BitRate(json.get("bit_rate"))

        tags = try? json.get("tags")
        language = tags?.language

        let width: Int = try json.get("width")
        let height: Int = try json.get("height")
        dimensions = (width, height)

        aspectRatio = try json.get("display_aspect_ratio")

        let framerateString: String = try json.get("avg_frame_rate")
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

        bitDepth = try? json.get("bits_per_raw_sample")
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
    var language: Language?
    var sampleRate: SampleRate
    var channels: Int
    var channelLayout: ChannelLayout

    var description: String {
        return ""
    }

    init(stream str: String) throws {
        try self.init(json: JSON.Parser.parse(str))
    }

    init(json: JSON) throws {
        index = try json.get("index")
        rawCodec = try json.get("codec_name")
        let t: CodecType = try CodecType(rawValue: json.get("codec_type")) ?? .unknown
        guard t == self.type else {
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
        codec = try AudioCodec(rawValue: json.get("codec_name")) ?? UnknownCodec.unknown_or_new(json.get("codec_name"))

        duration = try MediaDuration(json.get("duration"))

        bitRate = try BitRate(json.get("bit_rate"))

        tags = try? json.get("tags")

        language = tags?.language ?? .und

        sampleRate = try SampleRate(json.get("sample_rate"))

        channels = try json.get("channels")

        channelLayout = ChannelLayout(rawValue: try json.get("channel_layout")) ?? .unknown_or_new
    }
}

protocol Container {}

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

enum ChannelLayout: String {
    case mono
    case stereo
    case unknown_or_new
}

struct MediaDuration {
    var hours: UInt
    var minutes: UInt
    var seconds: UInt
    var description: String {
        var d = ""
        if hours > 0 {
            d += "\(hours):"
        }
        d += String(format: "%02d:%02d", minutes, seconds)
        return d
    }

    init(_ durationString: String) throws {
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
            guard let s = UInt(durationString) else {
                throw FFProbeError.DurationError.cannotConvertStringToUInt(type: "seconds", string: durationString)
            }
            seconds = s
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

struct BitRate {
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

    init(_ bitRateString: String) throws {
        if bitRateString.ends(with: "Mbit/s") {
            unit = .mbps
            guard let v = Double(bitRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.BitRateError.unableToConvertStringToDouble(bitRateString.components(separatedBy: " ")[0])
            }
            value = v
        } else if bitRateString.ends(with: "Kbit/s") {
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

struct SampleRate {
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

    init(_ sampleRateString: String) throws {
        if sampleRateString.ends(with: "mHz") {
            unit = .mhz
            guard let v = Double(sampleRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.SampleRateError.unableToConvertStringToDouble(sampleRateString.components(separatedBy: " ")[0])
            }
            value = v
        } else if sampleRateString.ends(with: "kHz") {
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

enum Language: String {
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

struct Tags: JSONInitializable {
    var language: Language?

    init(json: JSON) throws {
        if let languageString: String = try? json.get("language") {
            language = Language(rawValue: languageString)
        }
    }
}
