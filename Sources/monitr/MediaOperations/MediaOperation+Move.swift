//
//  MediaOperation+Move.swift
//  Plex-MonitrPackageDescription
//
//  Created by Jacob Williams on 03/01/18
//

import SwiftyBeaver
import Foundation
import PathKit

final class MoveOperation<MediaType: Media>: MediaOperation<MediaType> {
    var plexDirectory: Path
    var deleteSubtitles: Bool

    private enum MoveCodingKeys: String, CodingKey {
        case plexDirectory
        case deleteSubtitles
    }

    init(_ media: MediaType, logger: SwiftyBeaver.Type, plexDirectory: Path, deleteSubtitles: Bool) {
        self.plexDirectory = plexDirectory
        self.deleteSubtitles = deleteSubtitles
        super.init(media, logger: logger)
        self.qualityOfService = .background
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: MoveCodingKeys.self)

        plexDirectory = try values.decode(Path.self, forKey: .plexDirectory)
        deleteSubtitles = try values.decode(Bool.self, forKey: .deleteSubtitles)
        try super.init(from: decoder)
        self.qualityOfService = .background
    }

    override func main() {
        logger.debug("Moving \(media.path)")
        if !dependencies.isEmpty {
            media = (dependencies.first! as! MediaOperation).media
        }

        do {
            let state: MediaState = try media.move(to: plexDirectory, logger: logger)

            switch state {
            case .subtitle(_, let s):
                logger.warning("Failed to move subtitle '\(s.path)' to plex")
            case .unconverted(.failed(_, let u)):
                logger.warning("Failed to move unconverted \(MediaType.self) media '\(u.path)' to plex")
            case .failed(.moving, let f):
                logger.warning("Failed to move \(MediaType.self) media '\(f.path)' to plex")
            case .failed(.deleting, let f):
                logger.warning("Failed to delete \(MediaType.self) media '\(f.path)'")
            default: break
            }
        } catch {
            logger.error("Failed to move '\(media.path)'")
            logger.debug(error)
        }

        do {
            if deleteSubtitles && media is Video {
                logger.verbose("Removing subtitles")
                try (media as! Video).deleteSubtitles()
            }
        } catch {
            logger.error("Failed to delete subtitles from : \(media.path)")
            logger.debug(error)
        }

        // Once we've moved the file out of the downloads directory, it should
        // no longer be in the array of media the monitrs are processing
        guard let index = media.mainMonitr.currentMedia.index(where: { $0.path == media.path }) else {
            logger.error("Unable to find media item in the mainMonitr")
            return
        }
        media.mainMonitr.currentMedia.remove(at: index)
    }
}
