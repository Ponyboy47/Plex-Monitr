protocol Container: Codable {}

enum VideoContainer: String, Container {
    case mp4
    case m4v
    case mkv
}

enum AudioContainer: String, Container {
    case aac
    case ac3
    case mp3
}
