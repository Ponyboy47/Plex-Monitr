/*

 IgnoredMedia.swift

 Created By: Jacob Williams
 Description: This file contains the Ignored media structure for easy management of downloaded files
 License: MIT License

 */

import Foundation
import PathKit
import Downpour
import SwiftyBeaver
import JSON

/// Management for media types that we don't care about and can just delete
final class Ignore: Media {
    var plexName: String = ""

    static var supportedExtensions: [String] = ["txt", "png", "jpg", "jpeg",
                                                "gif", "rst", "md", "nfo",
                                                "sfv", "sub", "idx", "css",
                                                "js", "htm", "html", "url",
                                                "php", "md5", "doc", "docx",
                                                "rtf", "db"]

    var path: Path
    var isHomeMedia: Bool = false
    var downpour: Downpour

     var finalDirectory: Path {
        return "/dev/null"
    }

    init(_ path: Path) throws {
        if !path.string.lowercased().contains("sample") && !path.string.lowercased().contains(".ds_store") {
            guard Ignore.isSupported(ext: path.extension ?? "") else {
                throw MediaError.unsupportedFormat(path.extension ?? "")
            }
        }

        // Set the media file's path to the absolute path
        self.path = path.absolute
        // Create the downpour object
        downpour = Downpour(fullPath: path)
    }

    func move(to plexPath: Path, log: SwiftyBeaver.Type) throws -> Media {
        guard path.isDeletable else {
            throw MediaError.fileNotDeletable
        }
        log.verbose("Deleting ignorable file: \(path.string)")
        try path.delete()
        path = ""
        return self
    }
}
