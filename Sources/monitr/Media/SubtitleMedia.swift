//
//  Subtitle.swift
//  Plex-MonitrPackageDescription
//
//  Created by Jacob Williams on 11/22/17.
//

import PathKit
import Downpour

extension Video {
    final class Subtitle: Media, Equatable {
        var path: Path
        var isHomeMedia: Bool = false
        var downpour: Downpour
        var linkedVideo: Video?

        var plexName: String {
            if let lV = linkedVideo {
                return lV.plexName
            }

            guard !isHomeMedia else {
                return path.lastComponentWithoutExtension
            }

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

            // Return the calulated name
            return name
        }
        var plexFilename: String {
            var language: String?
            if let match = path.lastComponent.range(of: "anoXmous_([a-z]{3})", options: .regularExpression) {
                language = String(path.lastComponent[match]).replacingOccurrences(of: "anoXmous_", with: "")
            } else {
                for lang in commonLanguages {
                    if path.lastComponent.lowercased().contains(lang) || path.lastComponent.lowercased().contains(".\(lang[..<3]).") {
                        language = String(lang[..<3])
                        break
                    }
                }
            }

            var name = "\(plexName)."
            if let l = language {
                name += "\(l)."
            } else {
                name += "unknown-\(path.lastComponent)."
            }
            name += path.extension ?? "uft"
            return name
        }
        var finalDirectory: Path {
            if let lV = linkedVideo {
                return lV.finalDirectory
            }

            guard !isHomeMedia else {
                return Path("Home Videos\(Path.separator)\(plexName)")
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

        static var supportedExtensions: [String] = ["srt", "smi", "ssa", "ass",
                                                    "vtt"]

        /// Common subtitle languages to look out for
        private let commonLanguages: [String] = [
            "english", "spanish", "portuguese",
            "german", "swedish", "russian",
            "french", "chinese", "japanese",
            "hindu", "persian", "italian",
            "greek"
        ]

        init(_ path: Path) throws {
            // Check to make sure the extension of the video file matches one of the supported plex extensions
            guard Subtitle.isSupported(ext: path.extension ?? "") else {
                throw MediaError.unsupportedFormat(path.extension ?? "")
            }

            // Set the media file's path to the absolute path
            self.path = path.absolute
            // Create the downpour object
            self.downpour = Downpour(fullPath: path)

            if self.downpour.type == .tv {
                guard self.downpour.season != nil else {
                    throw MediaError.DownpourError.missingTVSeason(path.string)
                }
                guard self.downpour.episode != nil else {
                    throw MediaError.DownpourError.missingTVEpisode(path.string)
                }
            }
        }

        func delete() throws {
            try self.path.delete()
        }

        static func == (lhs: Subtitle, rhs: Subtitle) -> Bool {
            return lhs.path == rhs.path
        }
        static func == <T: Media>(lhs: Subtitle, rhs: T) -> Bool {
            return lhs.path == rhs.path
        }
        static func == <T: Media>(lhs: T, rhs: Subtitle) -> Bool {
            return lhs.path == rhs.path
        }
    }
}
