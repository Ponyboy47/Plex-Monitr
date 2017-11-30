typealias FFProbeAllStreamsProtocol = FFProbeVideoStreamProtocol & FFProbeAudioStreamProtocol

struct FFProbeStream: FFProbeAllStreamsProtocol {
    var index: Int
    var type: CodecType
    var rawCodec: String?
    var codec: Codec?
    var duration: MediaDuration?
    var bitRate: BitRate?
    var dimensions: (Int, Int)?
    var aspectRatio: String?
    var framerate: FrameRate?
    var bitDepth: Int?
    var sampleRate: SampleRate?
    var channels: Int?
    var channelLayout: ChannelLayout?
    var tags: Tags?

    var description: String {
        return ""
    }

    enum CodingKeys: String, CodingKey {
        case index
        case type = "codec_type"
        case rawCodec = "codec_name"
        case duration
        case bitRate = "bit_rate"
        case width
        case height
        case aspectRatio = "display_aspect_ratio"
        case framerate = "avg_frame_rate"
        case bitDepth = "bits_per_raw_sample"
        case sampleRate = "sample_rate"
        case channels
        case channelLayout = "channel_layout"
        case tags
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        index = try values.decode(Int.self, forKey: .index)
        type = try values.decode(CodecType.self, forKey: .type)
        rawCodec = try values.decodeIfPresent(String.self, forKey: .rawCodec)
        if let vCodec = try? VideoCodec(rawValue: rawCodec) {
            codec = vCodec
        } else if let aCodec = try? AudioCodec(rawValue: rawCodec) {
            codec = aCodec
        } else if let sCodec = try? SubtitleCodec(rawValue: rawCodec) {
            codec = sCodec
        }
        duration = try values.decodeIfPresent(MediaDuration.self, forKey: .duration)
        bitRate = try values.decodeIfPresent(BitRate.self, forKey: .bitRate)
        let width = try values.decodeIfPresent(Int.self, forKey: .width)
        let height = try values.decodeIfPresent(Int.self, forKey: .height)
        if let w = width, let h = height {
            dimensions = (w, h)
        }
        aspectRatio = try values.decodeIfPresent(String.self, forKey: .aspectRatio)
        framerate = try values.decodeIfPresent(FrameRate.self, forKey: .framerate)
        if let bD = try values.decodeIfPresent(String.self, forKey: .bitDepth) {
            bitDepth = Int(bD)
        }
        sampleRate = try values.decodeIfPresent(SampleRate.self, forKey: .sampleRate)
        channels = try values.decodeIfPresent(Int.self, forKey: .channels)
        channelLayout = try values.decodeIfPresent(ChannelLayout.self, forKey: .channelLayout)
        tags = try values.decodeIfPresent(Tags.self, forKey: .tags)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(index, forKey: .index)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(rawCodec, forKey: .rawCodec)
        if let vCodec = codec as? VideoCodec {
            try container.encode(vCodec, forKey: .rawCodec)
        } else if let aCodec = codec as? AudioCodec {
            try container.encode(aCodec, forKey: .rawCodec)
        }
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(bitRate, forKey: .bitRate)
        try container.encodeIfPresent(dimensions?.0, forKey: .width)
        try container.encodeIfPresent(dimensions?.1, forKey: .height)
        try container.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
        try container.encodeIfPresent(framerate, forKey: .framerate)
        if let bD = bitDepth {
            try container.encode("\(bD)", forKey: .bitDepth)
        }
        try container.encodeIfPresent(sampleRate, forKey: .sampleRate)
        try container.encodeIfPresent(channels, forKey: .channels)
        try container.encodeIfPresent(channelLayout, forKey: .channelLayout)
        try container.encodeIfPresent(tags, forKey: .tags)
    }
}
