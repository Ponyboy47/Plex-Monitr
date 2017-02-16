import Foundation

class Config {
    let plexDir: String
    let torrentDir: String
    let watchTime: Float
    let convert = false

    init(plexDir: String = "/var/lib/plexmediaserver/Library", torrentDir: String = "/var/lib/deluge", watchTime: Float = 60.0, convert: Bool = false) {
        self.plexDir = plexDir
        self.torrentDir = torrentDir
        self.watchTime = watchTime
        self.convert = convert
    }

    init(withFile path: String) {
    }
}
