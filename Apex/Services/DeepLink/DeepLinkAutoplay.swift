import Foundation

/// One-shot flag so Top Shelf's Play action can start the in-progress episode
/// after the series detail screen has loaded its episode list.
enum DeepLinkAutoplay {
    private static var pendingSeriesTMDBId: Int?

    static func setPending(seriesTMDBId: Int) {
        pendingSeriesTMDBId = seriesTMDBId
    }

    static func consume(seriesTMDBId: Int?) -> Bool {
        guard let pending = pendingSeriesTMDBId, pending == seriesTMDBId else { return false }
        pendingSeriesTMDBId = nil
        return true
    }
}
