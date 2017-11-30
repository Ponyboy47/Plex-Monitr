import Foundation

/// Struct for all of the streams returned by the `ffprobe` command
struct FFProbe: Codable {
    fileprivate var streams: [FFProbeStream] = []
    var videoStreams: [VideoStream] = []
    var audioStreams: [AudioStream] = []
    var dataStreams: [DataStream] = []
    var subtitleStreams: [SubtitleStream] = []

    enum CodingKeys: String, CodingKey {
        case streams
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        streams = try values.decode([FFProbeStream].self, forKey: .streams)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let vStreams = streams.filter { $0.type == .video }
        videoStreams = try decoder.decode([VideoStream].self, from: encoder.encode(vStreams))
        let aStreams = streams.filter { $0.type == .audio }
        audioStreams = try decoder.decode([AudioStream].self, from: encoder.encode(aStreams))
        let dStreams = streams.filter { $0.type == .data }
        dataStreams = try decoder.decode([DataStream].self, from: encoder.encode(dStreams))
        let sStreams = streams.filter { $0.type == .subtitle }
        subtitleStreams = try decoder.decode([SubtitleStream].self, from: encoder.encode(sStreams))
    }
}
