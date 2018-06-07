struct AspectRatio: RawRepresentable, Codable, Comparable, CustomStringConvertible {
    let rawValue: Double
    var description: String {
        switch self {
        case .x36x10: return "36:10"
        case .x21x9: return "21:9"
        case .x18x9: return "18:9"
        case .x16x9: return "16:9"
        case .x9x16: return "9:16"
        case .x4x3: return "4:3"
        case .square: return "1:1"
        default: return "unknown"
        }
    }

    static let x36x10: AspectRatio = .x3_6x1
    static let x21x9: AspectRatio = .x7x3
    static let x18x9: AspectRatio = .x2x1
    static let x16x9: AspectRatio = AspectRatio(rawValue: 16.0/9.0)
    static let x9x16: AspectRatio = AspectRatio(rawValue: 9.0/16.0)
    static let x7x3: AspectRatio = AspectRatio(rawValue: 7.0/3.0)
    static let x4x3: AspectRatio = AspectRatio(rawValue: 4.0/3.0)
    static let x3_6x1: AspectRatio = AspectRatio(rawValue: 3.6/1.0)
    static let x2x1: AspectRatio = AspectRatio(rawValue: 2.0/1.0)
    static let square: AspectRatio = AspectRatio(rawValue: 1)
    static let vertical: AspectRatio = .x9x16
    static let unknown: AspectRatio = AspectRatio(rawValue: -1)

    init(_ str: String, separatedBy delimiter: String = ":") {
        var comps = str.components(separatedBy: delimiter)

        if comps.count == 2 {
            rawValue = Double(comps[0])! / Double(comps[1])!
        } else {
            self = AspectRatio.unknown
        }
    }

    init(rawValue: Double) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        try container.encode(description)
    }

    static func == (lhs: AspectRatio, rhs: AspectRatio) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

    static func < (lhs: AspectRatio, rhs: AspectRatio) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}
