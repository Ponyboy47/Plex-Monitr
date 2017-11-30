protocol FFProbeAudioStreamProtocol: FFProbeCodecStreamProtocol {
    var sampleRate: SampleRate? { get set }
    var channels: Int? { get set }
    var channelLayout: ChannelLayout? { get set }
}

struct AudioStream: FFProbeAudioStreamProtocol {
    var index: Int
    var rawCodec: String?
    var type: CodecType = .audio
    var codec: Codec?
    var duration: MediaDuration?
    var bitRate: BitRate?
    var tags: Tags?
    var sampleRate: SampleRate?
    var channels: Int?
    var channelLayout: ChannelLayout?

    var description: String {
        var str = "\(self.indent)Index: \(index)"
        str += "\n\(self.indent)Type: \(type)"
        str += "\n\(self.indent)Codec: \(codec!)"
        if var bR = bitRate {
            str += "\n\(self.indent)BitRate: \(bR.kbps) kb/s"
        }
        if let d = duration {
            str += "\n\(self.indent)Duration: \(d.description)"
        }
        var sR = sampleRate
        str += "\n\(self.indent)Sample Rate: \(sR!.khz) kHz"
        str += "\n\(self.indent)Channels: \(channels!)"
        str += "\n\(self.indent)Layout: \(channelLayout!)"
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
        case sampleRate = "sample_rate"
        case channels
        case channelLayout = "channel_layout"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        index = try values.decode(Int.self, forKey: .index)
        rawCodec = try values.decode(String.self, forKey: .rawCodec)

        let t = try values.decode(CodecType.self, forKey: .type)
        guard t == type else {
            throw FFProbeError.incorrectTypeError(t)
        }
        guard let c = try? values.decode(AudioCodec.self, forKey: .rawCodec) else {
            throw FFProbeError.JSONParserError.unknownCodec(rawCodec!)
        }
        codec = c

        duration = try values.decodeIfPresent(MediaDuration.self, forKey: .duration)

        bitRate = try values.decodeIfPresent(BitRate.self, forKey: .bitRate)

        tags = try values.decodeIfPresent(Tags.self, forKey: .tags)

        sampleRate = try values.decode(SampleRate.self, forKey: .sampleRate)

        channels = try values.decode(Int.self, forKey: .channels)

        channelLayout = try values.decodeIfPresent(ChannelLayout.self, forKey: .channelLayout)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(index, forKey: .index)
        try container.encode(type, forKey: .type)
        try container.encode(rawCodec, forKey: .rawCodec)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(bitRate, forKey: .bitRate)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(channels, forKey: .channels)
        try container.encodeIfPresent(channelLayout, forKey: .channelLayout)
        try container.encodeIfPresent(tags, forKey: .tags)
    }
}
