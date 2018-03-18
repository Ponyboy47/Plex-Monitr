enum FFProbeError: Error {
    enum JSONParserError: Error {
        case unknownCodec(String)
        case framerateIsNotDouble(String)
        case cannotCalculateFramerate(String)
    }
    enum DurationError: Error {
        case unknownDuration(String)
        case cannotConvertStringToUInt(type: String, string: String)
        case cannotConvertStringToDouble(type: String, string: String)
    }
    enum BitRateError: Error {
        case unableToConvertStringToDouble(String)
    }
    enum SampleRateError: Error {
        case unableToConvertStringToDouble(String)
    }
    case incorrectTypeError(CodecType)
}
