protocol FFProbeStreamProtocol: Codable, CustomStringConvertible {
    var index: Int { get set }
    var type: CodecType { get set }
    var duration: MediaDuration? { get set }
    var bitRate: BitRate? { get set }
    var tags: Tags? { get set }
    var language: Language? { get }
    var description: String { get }
    var indent: String { get }
}

extension FFProbeStreamProtocol {
    var language: Language? {
        return tags?.language ?? .und
    }
    var indent: String {
        return "\t\t"
    }
}

protocol FFProbeCodecStreamProtocol: FFProbeStreamProtocol {
    var rawCodec: String? { get set }
    var codec: Codec? { get set }
}
