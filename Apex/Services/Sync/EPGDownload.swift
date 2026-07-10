//
//  EPGDownload.swift
//  Apex
//
//  Shared post-download prep for XMLTV guide files. Providers often serve
//  gzip-compressed guides without Content-Encoding, so URLSession leaves the
//  file compressed on disk until we decompress it here.
//

import Foundation
import OSLog

nonisolated enum EPGDownload {
    /// Returns a plain XML file URL, decompressing gzip when needed.
    static func preparedXMLTV(at fileURL: URL, deleteOriginalIfGzip: Bool) throws -> URL {
        guard GzipFile.isGzip(fileURL) else { return fileURL }
        Logger.network.info("EPG file is gzipped, decompressing")
        let decompressed = try GzipFile.decompress(fileURL)
        if deleteOriginalIfGzip {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return decompressed
    }
}
