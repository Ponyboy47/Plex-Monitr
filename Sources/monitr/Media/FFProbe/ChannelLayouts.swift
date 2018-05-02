enum ChannelLayout: String, Codable, Comparable {
    var intValue: Int {
        switch self {
        case .mono: return 0
        case .stereo: return 2
        case .five: return 6
        case .seven: return 8
        }
    }

    case mono
    case stereo
    case five = "5.1(side)"
    case seven = "7.1"

    static func == (lhs: ChannelLayout, rhs: ChannelLayout) -> Bool {
        return lhs.intValue == rhs.intValue
    }
    static func < (lhs: ChannelLayout, rhs: ChannelLayout) -> Bool {
        return lhs.intValue < rhs.intValue
    }
}
