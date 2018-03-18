protocol FFProbeVideoStreamProtocol: FFProbeCodecStreamProtocol {
    var dimensions: (Int, Int)? { get set }
    var aspectRatio: String? { get set }
    var framerate: FrameRate? { get set }
    var bitDepth: Int? { get set }
}

struct VideoStream: FFProbeVideoStreamProtocol {
    var index: Int
    var rawCodec: String?
    var type: CodecType = .video
    var codec: Codec?
    var duration: MediaDuration?
    var bitRate: BitRate?
    var tags: Tags?
    var dimensions: (Int, Int)?
    var aspectRatio: String?
    var framerate: FrameRate?
    var bitDepth: Int?

    var description: String {
        var str = "\(self.indent)Index: \(self.self.indent)"
        str += "\n\(self.indent)Type: \(type)"
        str += "\n\(self.indent)Codec: \(codec!)"
        if var bR = bitRate {
            str += "\n\(self.indent)BitRate: \(bR.kbps) kb/s"
        }
        if let d = duration {
            str += "\n\(self.indent)Duration: \(d.description)"
        }
        str += "\n\(self.indent)Dimensions: \(dimensions!.0)x\(dimensions!.1)"
        str += "\n\(self.indent)Aspect Ratio: \(aspectRatio!)"
        str += "\n\(self.indent)Framerate: \(framerate!.value) fps"
        if let b = bitDepth {
            str += "\n\(self.indent)Bit Depth: \(b)"
        }
        if let l = language {
            str += "\n\(self.indent)Language: \(l)"
        }
        if let t = tags {
            str += "\n\(self.indent)Tags: \(t)"
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

        let t = try values.decode(CodecType.self, forKey: .type)
        guard t == type else {
            throw FFProbeError.incorrectTypeError(t)
        }

        guard let c = try? values.decode(VideoCodec.self, forKey: .rawCodec) else {
            throw FFProbeError.JSONParserError.unknownCodec(rawCodec!)
        }
        codec = c

        duration = try values.decodeIfPresent(MediaDuration.self, forKey: .duration)

        bitRate = try values.decodeIfPresent(BitRate.self, forKey: .bitRate)

        let width = try values.decode(Int.self, forKey: .width)
        let height = try values.decode(Int.self, forKey: .height)
        dimensions = (width, height)

        aspectRatio = try values.decode(String.self, forKey: .aspectRatio)

        framerate = try values.decode(FrameRate.self, forKey: .framerate)

       let bD = try values.decode(String.self, forKey: .bitDepth)
       bitDepth = Int(bD)

       tags = try values.decodeIfPresent(Tags.self, forKey: .tags)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(index, forKey: .index)
        try container.encode(type, forKey: .type)
        try container.encode(rawCodec, forKey: .rawCodec)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(bitRate, forKey: .bitRate)
        try container.encode(dimensions!.0, forKey: .width)
        try container.encode(dimensions!.1, forKey: .height)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(framerate, forKey: .framerate)
        try container.encode(bitDepth, forKey: .bitDepth)
        try container.encodeIfPresent(tags, forKey: .tags)
    }
}
