struct FrameRate: Codable {
    var value: Double

    init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()

        let framerateString = try values.decode(String.self)
        if framerateString.contains("/") {
            let components = framerateString.components(separatedBy: "/")
            guard components.count == 2, let top = Double(components[0]), let bottom = Double(components[1]) else {
                throw FFProbeError.JSONParserError.cannotCalculateFramerate(framerateString)
            }
            var f = top / bottom
            if f < 0 {
                f = 0
            }
            value = f
        } else {
            guard var f = Double(framerateString) else {
                throw FFProbeError.JSONParserError.framerateIsNotDouble(framerateString)
            }
            if f < 0 {
                f = 0
            }
            value = f
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        try container.encode("\(value)")
    }
}
