import CloudKit
import Foundation

struct CloudKitSyncService {
    private let database = CKContainer.default().privateCloudDatabase
    private let recordID = CKRecord.ID(recordName: "LedgerSnapshot")

    func sync(local: PersistedState) async throws -> PersistedState {
        var state = local
        var lastError: Error?

        for _ in 0..<3 {
            do {
                let record = try await fetchRecord()
                if let record, let remote = try decode(record: record) {
                    state = merge(state, remote)
                }
                state.settings.iCloudSyncEnabled = local.settings.iCloudSyncEnabled
                state.settings.lastSyncDate = Date()

                let data = try encode(state)
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("JianJiSync_\(UUID().uuidString).json")
                try data.write(to: fileURL, options: .atomic)
                defer { try? FileManager.default.removeItem(at: fileURL) }

                let upload = record ?? CKRecord(recordType: "LedgerSnapshot", recordID: recordID)
                upload["payload"] = CKAsset(fileURL: fileURL)
                _ = try await save(upload)
                return state
            } catch let error as CKError where error.code == .serverRecordChanged {
                lastError = error
            } catch {
                throw error
            }
        }
        throw lastError ?? CKError(.serverRecordChanged)
    }

    private func fetchRecord() async throws -> CKRecord? {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                database.fetch(withRecordID: recordID) { record, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let record {
                        continuation.resume(returning: record)
                    } else {
                        continuation.resume(throwing: CKError(.unknownItem))
                    }
                }
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func save(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedRecord {
                    continuation.resume(returning: savedRecord)
                } else {
                    continuation.resume(throwing: CKError(.internalError))
                }
            }
        }
    }

    private func encode(_ state: PersistedState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(state)
    }

    private func decode(record: CKRecord) throws -> PersistedState? {
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersistedState.self, from: Data(contentsOf: url))
    }

    private func merge(_ local: PersistedState, _ remote: PersistedState) -> PersistedState {
        let deletedTransactions = mergeDates(local.deletedTransactionIDs, remote.deletedTransactionIDs)
        let deletedCategories = mergeDates(local.deletedCategoryIDs, remote.deletedCategoryIDs)

        var transactions = Dictionary(uniqueKeysWithValues: local.transactions.map { ($0.id.uuidString, $0) })
        for transaction in remote.transactions {
            let key = transaction.id.uuidString
            if let existing = transactions[key], existing.updatedAt >= transaction.updatedAt { continue }
            transactions[key] = transaction
        }
        var mergedTransactions = transactions.values.filter { transaction in
            guard let deleted = deletedTransactions[transaction.id.uuidString] else { return true }
            return transaction.updatedAt > deleted
        }

        var categories = Dictionary(uniqueKeysWithValues: local.categories.map { ($0.id, $0) })
        for category in remote.categories {
            if let existing = categories[category.id], existing.updatedAt >= category.updatedAt { continue }
            categories[category.id] = category
        }
        let mergedCategories = categories.values.filter { category in
            guard let deleted = deletedCategories[category.id] else { return true }
            return category.updatedAt > deleted
        }
        let validCategoryIDs = Set(mergedCategories.map(\.id))
        for index in mergedTransactions.indices where mergedTransactions[index].type != .transfer {
            if !validCategoryIDs.contains(mergedTransactions[index].categoryID) {
                mergedTransactions[index].categoryID = mergedTransactions[index].type == .income
                    ? LedgerCategory.incomeFallbackID : LedgerCategory.expenseFallbackID
            }
        }

        var settings = local.settings.updatedAt >= remote.settings.updatedAt ? local.settings : remote.settings
        settings.iCloudSyncEnabled = local.settings.iCloudSyncEnabled
        return PersistedState(
            transactions: mergedTransactions.sorted { $0.date > $1.date },
            categories: mergedCategories.sorted { $0.updatedAt < $1.updatedAt },
            settings: settings,
            deletedTransactionIDs: deletedTransactions,
            deletedCategoryIDs: deletedCategories
        )
    }

    private func mergeDates(_ lhs: [String: Date], _ rhs: [String: Date]) -> [String: Date] {
        var result = lhs
        for (key, date) in rhs {
            result[key] = max(result[key] ?? .distantPast, date)
        }
        return result
    }
}
