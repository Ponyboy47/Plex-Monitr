struct DataStream: FFProbeStreamProtocol {
    var index: Int
    var type: CodecType = .data
    var duration: MediaDuration?
    var bitRate: BitRate?
    var tags: Tags?

    var description: String {
        var str = "\(indent)Index: \(index)"
        if var bR = bitRate {
            str += "\n\(indent)BitRate: \(bR.kbps) kb/s"
        }
        if let d = duration {
            str += "\n\(indent)Duration: \(d.description)"
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
        case type = "codec_type"
        case duration
        case bitRate = "bit_rate"
        case tags
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        index = try values.decode(Int.self, forKey: .index)

        let t = try values.decode(CodecType.self, forKey: .type)
        guard t == type else {
            throw FFProbeError.incorrectTypeError(t)
        }

        duration = try values.decodeIfPresent(MediaDuration.self, forKey: .duration)

        bitRate = try values.decodeIfPresent(BitRate.self, forKey: .bitRate)

        tags = try values.decodeIfPresent(Tags.self, forKey: .tags)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(index, forKey: .index)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(bitRate, forKey: .bitRate)
        try container.encodeIfPresent(tags, forKey: .tags)
    }
}
