// swiftlint:disable identifier_name

struct SampleRate: Codable, Comparable {
    enum SampleRateUnit: String {
        case hz
        case khz
        case mhz
    }
    private var value: Double
    private var unit: SampleRateUnit
    lazy var hz: Double = {
        switch self.unit {
        case .hz:
            return self.value
        case .khz:
            return self.value * 1000.0
        case .mhz:
            return self.value * 1000.0 * 1000.0
        }
    }()
    lazy var khz: Double = {
        switch self.unit {
        case .hz:
            return self.value / 1000.0
        case .khz:
            return self.value
        case .mhz:
            return self.value * 1000.0
        }
    }()
    lazy var mhz: Double = {
        switch self.unit {
        case .hz:
            return self.value / 1000.0 / 1000.0
        case .khz:
            return self.value / 1000.0
        case .mhz:
            return self.value
        }
    }()

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let sampleRateString = try container.decode(String.self)

        if sampleRateString.hasSuffix("mHz") {
            unit = .mhz
            guard let v = Double(sampleRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.SampleRateError.unableToConvertStringToDouble(sampleRateString.components(separatedBy: " ")[0])
            }
            value = v
        } else if sampleRateString.hasSuffix("kHz") {
            unit = .khz
            guard let v = Double(sampleRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.SampleRateError.unableToConvertStringToDouble(sampleRateString.components(separatedBy: " ")[0])
            }
            value = v
        } else {
            unit = .hz
            guard let v = Double(sampleRateString.components(separatedBy: " ")[0]) else {
                throw FFProbeError.SampleRateError.unableToConvertStringToDouble(sampleRateString.components(separatedBy: " ")[0])
            }
            value = v
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        var other = self
        try container.encode("\(other.khz) kHz")
    }

    static func == (lhs: SampleRate, rhs: SampleRate) -> Bool {
        var l = lhs
        var r = rhs
        return l.hz == r.hz
    }

    static func < (lhs: SampleRate, rhs: SampleRate) -> Bool {
        var l = lhs
        var r = rhs
        return l.hz < r.hz
    }
}
