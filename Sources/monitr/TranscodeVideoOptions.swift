enum SizeTarget: String, CustomStringConvertible {
    case small
    case medium
    case big

    fileprivate static let all: [SizeTarget] = [.small, .medium, .big]

    var description: String {
        return rawValue
    }

    static func == (lhs: String, rhs: SizeTarget) -> Bool {
        return lhs == rhs.rawValue
    }
}

enum VideoProfile: String, CustomStringConvertible {
    case tosz = "2160p"
    case ozez = "1080p"
    case stz = "720p"
    case fez = "480p"

    fileprivate static let all: [VideoProfile] = [.tosz, .ozez, .stz, .fez]

    var description: String {
        return rawValue
    }

    static func == (lhs: String, rhs: VideoProfile) -> Bool {
        return lhs == rhs.rawValue
    }
}

struct Target: RawRepresentable, CustomStringConvertible, Equatable {
    let rawValue: _Target

    // swiftlint:disable type_name
    enum _Target: CustomStringConvertible, Equatable {
    // swiftlint:enable type_name
        case size(SizeTarget)
        case bitRate(VideoProfile, Int)

        var description: String {
            switch self {
            case .size(let size): return "Size(\(size.rawValue))"
            case .bitRate(let profile, let bitRate): return "BitRate(\(profile.rawValue)=\(bitRate))"
            }
        }

        static func == (lhs: _Target, rhs: _Target) -> Bool {
            if case .size = lhs, case .size = rhs {
                return true
            } else if case let .bitRate(lProfile, _) = lhs, case let .bitRate(rProfile, _) = rhs {
                return lProfile == rProfile
            }
            return false
        }
    }

    var description: String {
        return rawValue.description
    }

    init?(rawValue: String) {
        let targets = rawValue.components(separatedBy: "=")
        if targets.count == 1 {
            guard let size = SizeTarget(rawValue: rawValue) else { return nil }
            self.rawValue = .size(size)
        } else if targets.count == 2 {
            guard let profile = VideoProfile(rawValue: targets.first!) else { return nil }
            guard let bitRate = Int(targets.last!) else { return nil }
            self.rawValue = .bitRate(profile, bitRate)
        } else { return nil }
    }

    init(rawValue: _Target) {
        self.init(rawValue)
    }

    init(_ target: _Target) {
        rawValue = target
    }

    static func size(_ size: SizeTarget) -> Target {
        return Target(.size(size))
    }

    static func bitRate(_ profile: VideoProfile, _ bitRate: Int) -> Target {
        return Target(.bitRate(profile, bitRate))
    }

    static func == (lhs: Target, rhs: Target) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}

enum TranscodeSpeed: String {
    case `default`
    case quick
    case veryquick
}

enum X264Preset: String {
    case veryslow
    case slower
    case slow
    case `default`
    case fast
    case faster
    case veryfast
}
