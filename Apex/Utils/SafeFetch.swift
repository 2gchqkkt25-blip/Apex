import OSLog
import SwiftData

nonisolated enum SafeFetch {
    /// Fetches objects from a ModelContext with proper error logging.
    /// Returns an empty array on failure instead of silently swallowing errors.
    static func fetch<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        context: ModelContext,
        file: String = #fileID,
        line: Int = #line
    ) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            Logger.database.error(
                "SafeFetch failed for \(String(describing: T.self)) in \(file):\(line): \(error.localizedDescription)"
            )
            return []
        }
    }

    /// Fetches a count from a ModelContext with proper error logging.
    /// Returns 0 on failure instead of silently swallowing errors.
    static func fetchCount<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        context: ModelContext,
        file: String = #fileID,
        line: Int = #line
    ) -> Int {
        do {
            return try context.fetchCount(descriptor)
        } catch {
            Logger.database.error(
                "SafeFetch.count failed for \(String(describing: T.self)) in \(file):\(line): \(error.localizedDescription)"
            )
            return 0
        }
    }
}