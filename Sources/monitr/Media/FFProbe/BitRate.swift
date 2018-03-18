struct BitRate: Codable, Comparable {
    enum BitRateUnit: String {
        case bps
        case kbps
        case mbps
    }
    private var value: Double
    private var unit: BitRateUnit
    lazy var bps: Double = {
        switch self.unit {
        case .bps:
            return self.value
        case .kbps:
            return self.value * 1000.0
        case .mbps:
            return self.value * 1000.0 * 1000.0
        }
    }()
    lazy var kbps: Double = {
        switch self.unit {
        case .bps:
            return self.value / 1000.0
        case .kbps:
            return self.value
        case .mbps:
            return self.value * 1000.0
        }
    }()
    lazy var mbps: Double = {
        switch self.unit {
        case .bps:
            return self.value / 1000.0 / 1000.0
        case .kbps:
            return self.value / 1000.0
        case .mbps:
            return self.value
        }
    }()

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let bitRateString = try container.decode(String.self)

        if bitRateString.hasSuffix("Mbit/s") {
            unit = .mbps
            guard let v = Double(bitRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.BitRateError.unableToConvertStringToDouble(bitRateString.components(separatedBy: " ")[0])
            }
            value = v
        } else if bitRateString.hasSuffix("Kbit/s") {
            unit = .kbps
            guard let v = Double(bitRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.BitRateError.unableToConvertStringToDouble(bitRateString.components(separatedBy: " ")[0])
            }
            value = v
        } else {
            unit = .bps
            guard let v = Double(bitRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.BitRateError.unableToConvertStringToDouble(bitRateString.components(separatedBy: " ")[0])
            }
            value = v
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        var other = self
        try container.encode("\(other.kbps) Kbit/s")
    }

    static func == (lhs: BitRate, rhs: BitRate) -> Bool {
        var l = lhs
        var r = rhs
        return l.bps == r.bps
    }

    static func < (lhs: BitRate, rhs: BitRate) -> Bool {
        var l = lhs
        var r = rhs
        return l.bps < r.bps
    }
}
