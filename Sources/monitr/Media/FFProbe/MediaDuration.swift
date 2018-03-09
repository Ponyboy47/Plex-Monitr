struct MediaDuration: Codable, Comparable {
    var hours: UInt
    var minutes: UInt
    var seconds: UInt
    var description: String {
        var d = ""
        if hours > 0 {
            d += "\(hours):"
        }

        if hours > 0 || minutes > 0 {
            d += String(format: "%02d:", minutes)
        }

        d += String(format: "%02d", seconds)
        return d
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let durationString = try container.decode(String.self)
        let parts = durationString.components(separatedBy: ":")

        if parts.count == 3 {
            guard let h = UInt(parts[0]) else {
                throw FFProbeError.DurationError.cannotConvertStringToUInt(type: "hours", string: parts[0])
            }
            hours = h
            guard let m = UInt(parts[1]) else {
                throw FFProbeError.DurationError.cannotConvertStringToUInt(type: "minutes", string: parts[1])
            }
            minutes = m
            let splitSeconds = parts[2].components(separatedBy: ".")
            guard let s = UInt(splitSeconds[0]) else {
                throw FFProbeError.DurationError.cannotConvertStringToUInt(type: "seconds", string: splitSeconds[0])
            }
            seconds = s
        } else if parts.count == 2 {
            hours = 0
            guard let m = UInt(parts[0]) else {
                throw FFProbeError.DurationError.cannotConvertStringToUInt(type: "minutes", string: parts[0])
            }
            minutes = m
            let splitSeconds = parts[1].components(separatedBy: ".")
            guard let s = UInt(splitSeconds[0]) else {
                throw FFProbeError.DurationError.cannotConvertStringToUInt(type: "seconds", string: splitSeconds[0])
            }
            seconds = s
        } else if parts.count == 1 {
            guard let d = Double(durationString) else {
                throw FFProbeError.DurationError.cannotConvertStringToDouble(type: "seconds", string: durationString)
            }
            seconds = UInt(d)
            minutes = 0
            hours = 0
            while seconds >= 60 {
                minutes += 1
                seconds -= 60
            }
            hours = minutes / 60
            minutes %= 60
        } else {
            throw FFProbeError.DurationError.unknownDuration(durationString)
        }
    }

    init(double duration: Double) {
        hours = 0
        minutes = 0
        seconds = UInt(duration)
        while seconds >= 60 {
            seconds -= 60
            minutes += 1
            if minutes >= 60 {
                minutes -= 60
                hours += 1
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        try container.encode(description)
    }

    static func == (lhs: MediaDuration, rhs: MediaDuration) -> Bool {
        return lhs.hours == rhs.hours && lhs.minutes == rhs.minutes && lhs.seconds == rhs.seconds
    }

    static func < (lhs: MediaDuration, rhs: MediaDuration) -> Bool {
        if lhs.hours < rhs.hours {
            return true
        } else if lhs.hours == rhs.hours && lhs.minutes < rhs.minutes {
            return true
        } else if lhs.hours == rhs.hours && lhs.minutes == rhs.minutes && lhs.seconds < rhs.seconds {
            return true
        } else {
            return false
        }
    }
}
