import JSON

enum FFProbeError: Error {
    enum JSONParserError: Error {
        case unknownCodecType
        case framerateIsNotDouble(String)
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
}

struct FFProbe {
    fileprivate var streams: [FFProbeStream] = []
    lazy var videoStreams: [FFProbeStream] = {
        return self.streams.filter({ $0.codecType == .video })
    }()
    lazy var audioStreams: [FFProbeStream] = {
        return self.streams.filter({ $0.codecType == .audio })
    }()
    lazy var unknownStreams: [FFProbeStream] = {
        return self.streams.filter({ $0.codecType == .unknown })
    }()
    init() {}
}

extension FFProbe: JSONInitializable {
    init(_ ffprobeString: String) throws {
        try self.init(json: JSON.Parser.parse(ffprobeString))
    }

    init(json: JSON) throws {
        streams = try json.get("streams")
    }
}

struct FFProbeStream: JSONInitializable {
    var index: Int
    var rawCodec: String
    var codec: Codec
    var codecType: CodecType
    var dimensions: (Int, Int)
    var aspectRatio: String
    var duration: MediaDuration
    var framerate: Double?
    var bitRate: BitRate
    var bitDepth: Int?
    var sampleRate: SampleRate?
    var tags: Tags?
    var language: Language

    init(_ streamString: String) throws {
        try self.init(json: JSON.Parser.parse(streamString))
    }

    init(json: JSON) throws {
        index = try json.get("index")
        rawCodec = try json.get("codec_name")
        codecType = CodecType(rawValue: try json.get("codec_type")) ?? .unknown
        switch codecType {
        case .video:
            codec = VideoCodec(rawValue: try json.get("codec_name")) ?? VideoCodec.unknown_or_new
        case .audio:
            codec = AudioCodec(rawValue: try json.get("codec_name")) ?? AudioCodec.unknown_or_new
        default:
            throw FFProbeError.JSONParserError.unknownCodecType
        }

        let width: Int = try json.get("width")
        let height: Int = try json.get("height")
        dimensions = (width, height)

        aspectRatio = try json.get("display_aspect_ratio")

        let durationString: String = try json.get("duration")
        duration = try MediaDuration(durationString)

        let framerateString: String = (try? json.get("avg_frame_rate")) ?? ""
        if framerateString.contains("/") {
            let components = framerateString.components(separatedBy: "/")
            if let top = Double(components[0]), let bottom = Double(components[1]) {
                let f = top / bottom
                if f > 0.0 {
                    framerate = f
                }
            }
        } else if framerateString.contains(".") {
            guard let f = Double(framerateString) else {
                throw FFProbeError.JSONParserError.framerateIsNotDouble(framerateString)
            }
            if f > 0.0 {
                framerate = f
            }
        }

        let bitRateString: String = try json.get("bit_rate")
        bitRate = try BitRate(bitRateString)

        bitDepth = try? json.get("bits_per_raw_sample")

        let sampleRateString: String = try json.get("sample_rate")
        sampleRate = try? SampleRate(sampleRateString)

        tags = try? json.get("tags")

        language = tags?.language ?? .und
    }

    func print() -> String {
        let indent = "\t\t"
        var str = "\(indent)Index: \(index)"
        str += "\n\(indent)Codec: "
        if codecType == .video {
            if codec as! VideoCodec == .unknown_or_new {
                str += rawCodec
            } else {
                str += (codec as! VideoCodec).rawValue
            }
            str += "\n\(indent)Dimensions: \(dimensions.0)x\(dimensions.1)"
            str += "\n\(indent)Aspect Ratio: \(aspectRatio)"
            str += "\n\(indent)Framerate: \(framerate!) fps"
            str += "\n\(indent)Bit Depth: \(bitDepth!)"
        } else if codecType == .audio {
            if codec as! AudioCodec == .unknown_or_new {
                str += rawCodec
            } else {
                str += (codec as! AudioCodec).rawValue
            }
            var sR = sampleRate!
            str += "\n\(indent)Sample Rate: \(sR.khz) Khz"
        }
        var bR = bitRate
        str += "\n\(indent)BitRate: \(bR.kbps) kb/s"
        str += "\n\(indent)Duration: \(duration.description)"
        str += "\n\(indent)Language: \(language)"

        return str
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

enum CodecType: String {
    case video
    case audio
    case unknown
}

protocol Codec {}

enum VideoCodec: String, Codec {
    case h264
    case mpeg
    case any
    case unknown_or_new
}
enum AudioCodec: String, Codec {
    case aac
    case ac3
    case eac3
    case any
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
