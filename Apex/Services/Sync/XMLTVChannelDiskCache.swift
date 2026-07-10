//
//  XMLTVChannelDiskCache.swift
//  Apex
//
//  Streams matching XMLTV `<channel>` rows to a temp file so a 50MB+ worldwide
//  guide never builds a giant in-memory channel table during programme import.
//

import Foundation
import OSLog

nonisolated enum XMLTVChannelDiskCache {
  private static let fieldSeparator: UInt8 = 0x1F
  private static let lineSeparator = "\n".data(using: .utf8)!

  /// One SAX pass over `fileURL`, appending matching channel id + display names
  /// to a temp file. Returns the file URL when at least one channel was written.
  static func collect<C: EPGChannelIdentity>(
    fileURL: URL,
    catalog: EPGChannelCatalog,
    identities: [C]
  ) -> URL? {
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString + ".epg-channels")
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    guard let output = try? FileHandle(forWritingTo: destination) else { return nil }

    let collector = ChannelCollector(
      catalog: catalog,
      exactNameIndex: EPGStreamExactNameIndex(identities: identities),
      output: output
    )
    guard let parser = makeStreamingXMLParser(fileURL: fileURL) else {
      try? FileManager.default.removeItem(at: destination)
      return nil
    }
    parser.delegate = collector
    parser.parse()
    try? output.close()

    guard collector.wroteEntries else {
      try? FileManager.default.removeItem(at: destination)
      return nil
    }
    Logger.database.info("EPG channel disk cache: \(collector.entryCount) channels")
    return destination
  }

  static func loadIndex(from fileURL: URL) -> XMLTVChannelIndex {
    var map: [String: [String]] = [:]
    guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return .empty }
    defer { try? handle.close() }
    var buffer = Data()
    while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
      buffer.append(chunk)
      while let newline = buffer.firstIndex(of: 0x0A) {
        let lineData = buffer[..<newline]
        buffer.removeSubrange(...newline)
        if let line = String(data: lineData, encoding: .utf8) {
          parseLine(line, into: &map)
        }
      }
    }
    if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
      parseLine(line, into: &map)
    }
    return XMLTVChannelIndex(idToDisplayNames: map)
  }

  private static func parseLine(_ line: String, into map: inout [String: [String]]) {
    let parts = line.split(separator: "\u{1F}", omittingEmptySubsequences: false)
    guard let id = parts.first.map(String.init), !id.isEmpty else { return }
    let names = parts.dropFirst().map(String.init).filter { !$0.isEmpty }
    guard !names.isEmpty else { return }
    map[id] = names
  }

  private final class ChannelCollector: NSObject, XMLParserDelegate {
    private let catalog: EPGChannelCatalog
    private let exactNameIndex: EPGStreamExactNameIndex
    private let output: FileHandle
    private(set) var wroteEntries = false
    private(set) var entryCount = 0

    private var currentChannelID: String?
    private var currentNames: [String] = []
    private var currentDisplayName: String?
    private var currentText = ""

    init(catalog: EPGChannelCatalog, exactNameIndex: EPGStreamExactNameIndex, output: FileHandle) {
      self.catalog = catalog
      self.exactNameIndex = exactNameIndex
      self.output = output
    }

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
      currentText = ""
      if elementName == "channel" {
        currentChannelID = attributeDict["id"]
        currentNames = []
        currentDisplayName = nil
      }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
      guard currentText.count < 512 else { return }
      let remaining = 512 - currentText.count
      currentText += String(string.prefix(remaining))
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
      switch elementName {
      case "display-name":
        if currentChannelID != nil {
          let name = (currentDisplayName ?? "") + currentText
          let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty { currentNames.append(trimmed) }
          currentDisplayName = name
        }
      case "channel":
        commitChannel()
        currentChannelID = nil
        currentNames = []
        currentDisplayName = nil
      default:
        break
      }
      currentText = ""
    }

    private func commitChannel() {
      guard let channelID = currentChannelID, !currentNames.isEmpty else { return }
      let idMatch = catalog.matches(channelID)
      let nameMatch = exactNameIndex.matches(displayNames: currentNames)
      guard idMatch || nameMatch else {
        // Log first few unmatched channels that have "dummy-" prefix to diagnose.
        if channelID.hasPrefix("dummy-"), unmatchedLogCount < 5 {
          unmatchedLogCount += 1
          Logger.database.warning(
            "EPG channel unmatched — id: \(channelID, privacy: .public) names: \(self.currentNames.prefix(3).joined(separator: " | "), privacy: .public)"
          )
        }
        return
      }
      guard idMatch || entryCount < 2_500 else { return }

      var line = channelID
      for name in currentNames {
        line.append("\u{1F}")
        line.append(name)
      }
      guard let data = (line + "\n").data(using: .utf8) else { return }
      output.write(data)
      wroteEntries = true
      entryCount += 1
    }
    private var unmatchedLogCount = 0
  }
}
