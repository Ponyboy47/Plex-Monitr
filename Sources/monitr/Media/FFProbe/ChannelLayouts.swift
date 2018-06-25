enum ChannelLayout: String, Codable, Comparable {
    var intValue: Int {
        switch self {
        case .mono: return 0
        case .stereo: return 2
        case .four: return 4
        case .five: return 6
        case .five_side: return 6
        case .six: return 7
        case .seven: return 8
        }
    }

    case mono
    case stereo
    case four = "4.0"
    case five_side = "5.1(side)"
    case five = "5.1"
    case six = "6.1"
    case seven = "7.1"

    static func == (lhs: ChannelLayout, rhs: ChannelLayout) -> Bool {
        return lhs.intValue == rhs.intValue
    }
    static func < (lhs: ChannelLayout, rhs: ChannelLayout) -> Bool {
        return lhs.intValue < rhs.intValue
    }
}
