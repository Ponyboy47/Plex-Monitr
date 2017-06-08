/*

 OtherMedia.swift

 Created By: Jacob Williams
 Description: This file contains the other media structures for easy management of downloaded files
 License: MIT License

 */

import Foundation
import PathKit
import Downpour
import SwiftyBeaver
import JSON

final class Subtitle: BaseMedia {
    enum SupportedExtension: String {
        case srt
        case smi
        case ssa
        case ass
        case vtt
    }

    /// Common subtitle languages to look out for
    private let commonLanguages: [String] = [
        "english", "spanish", "portuguese",
        "german", "swedish", "russian",
        "french", "chinese", "japanese",
        "hindu", "persian", "italian",
        "greek"
    ]

    override var plexFilename: String {
        var name = "\(plexName)."
        if let l = lang {
            name += "\(l)."
        }
        name += path.extension ?? "uft"
        return name
    }
    override var plexName: String {
        var name: String
        switch downpour.type {
        // If it's a movie file, plex wants "Title (YYYY)"
        case .movie:
            name = "\(downpour.title.wordCased)"
            if let year = downpour.year {
                name += " (\(year))"
            }
        // If it's a tv show, plex wants "Title - sXXeYY"
        case .tv:
            name = "\(downpour.title.wordCased) - s\(String(format: "%02d", Int(downpour.season!)!))e\(String(format: "%02d", Int(downpour.episode!)!))"
        // Otherwise just return the title (shouldn't ever actually reach this)
        default:
            name = downpour.title.wordCased
        }
        var language: String?
        if let match = path.lastComponent.range(of: "anoXmous_([a-z]{3})", options: .regularExpression) {
            language = path.lastComponent[match].replacingOccurrences(of: "anoXmous_", with: "")
        } else {
            for lang in commonLanguages {
                if path.lastComponent.lowercased().contains(lang) || path.lastComponent.lowercased().contains(".\(lang.substring(to: 3)).") {
                    language = lang.substring(to: 3)
                    break
                }
            }
        }

        if let l = language {
            lang = l
        } else {
            lang = "unknown-\(path.lastComponent)"
        }

        // Return the calulated name
        return name
    }
    var lang: String?
    override var finalDirectory: Path {
        var name = plexName
        while name.contains("unknown") {
            name = Path(name).lastComponentWithoutExtension
        }
        var base: Path
        switch downpour.type {
        case .movie:
            base = Path("Movies\(Path.separator)\(plexName)")
        case .tv:
            base = Path("TV Shows\(Path.separator)\(downpour.title.wordCased)\(Path.separator)Season \(String(format: "%02d", Int(downpour.season!)!))\(Path.separator)\(plexName)")
        default:
            base = ""
        }
        return base
    }

    required init(_ path: Path) throws {
        try super.init(path)
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Subtitle.isSupported(ext: path.extension ?? "") else {
            throw MediaError.unsupportedFormat(path.extension ?? "")
        }

        if downpour.type == .tv {
            guard let _ = downpour.season else {
                throw MediaError.DownpourError.missingTVSeason(path.string)
            }
            guard let _ = downpour.episode else {
                throw MediaError.DownpourError.missingTVEpisode(path.string)
            }
        }
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        let p = Path(try json.get("path"))
        // Check to make sure the extension of the video file matches one of the supported plex extensions
        guard Subtitle.isSupported(ext: p.extension ?? "") else {
            throw MediaError.unsupportedFormat(p.extension ?? "")
        }
        try super.init(json: json)

        if downpour.type == .tv {
            guard let _ = downpour.season else {
                throw MediaError.DownpourError.missingTVSeason(p.string)
            }
            guard let _ = downpour.episode else {
                throw MediaError.DownpourError.missingTVEpisode(p.string)
            }
        }
    }

    override func move(to plexPath: Path, log: SwiftyBeaver.Type) throws {
        try super.move(to: plexPath, log: log)
    }

    override class func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}
