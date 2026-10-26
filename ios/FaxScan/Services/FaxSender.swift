import Foundation
import SwiftData

/// Turns the draft into a PDF, uploads it and records it in History.
@MainActor
enum FaxSender {
    static func send(draft: FaxDraft, jws: String, context: ModelContext) async throws -> FaxRecord {
        guard let number = draft.faxNumberE164 else {
            throw FaxAPI.APIError(code: "invalid_number", message: "Enter a valid 10-digit US or Canada fax number.")
        }
        let id = UUID()
        let pdf = FaxRecord.documentsFolder.appendingPathComponent("\(id.uuidString).pdf")
        let cover = draft.includeCover ? draft.effectiveCover : nil
        let pageURLs = draft.pages.map(\.fileURL)
        let total = draft.totalPages
        try await Task.detached(priority: .userInitiated) {
            try PDFBuilder.build(cover: cover, pages: pageURLs, totalPages: total, to: pdf)
        }.value

        do {
            let response = try await FaxAPI().send(pdf: pdf, to: number, transaction: jws)
            let record = FaxRecord(id: id, serverID: response.fax.id, recipientName: draft.recipientName,
                                   faxNumber: number, pageCount: response.fax.pages,
                                   status: FaxStatus(rawValue: response.fax.status) ?? .queued)
            context.insert(record)
            try? context.save()
            return record
        } catch {
            try? FileManager.default.removeItem(at: pdf)
            throw error
        }
    }

    /// Sends a fax from History again, with the same document and number.
    static func resend(_ original: FaxRecord, jws: String, context: ModelContext) async throws -> FaxRecord {
        let id = UUID()
        let copy = FaxRecord.documentsFolder.appendingPathComponent("\(id.uuidString).pdf")
        try FileManager.default.copyItem(at: original.documentURL, to: copy)
        do {
            let response = try await FaxAPI().send(pdf: copy, to: original.faxNumber, transaction: jws)
            let record = FaxRecord(id: id, serverID: response.fax.id, recipientName: original.recipientName,
                                   faxNumber: original.faxNumber, pageCount: response.fax.pages,
                                   status: FaxStatus(rawValue: response.fax.status) ?? .queued)
            context.insert(record)
            try? context.save()
            return record
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
    }

    static func refresh(_ records: [FaxRecord]) async {
        let api = FaxAPI()
        for record in records where !record.status.isFinal {
            guard let fax = try? await api.status(of: record.serverID),
                  let status = FaxStatus(rawValue: fax.status) else { continue }
            if status != record.status || fax.failureMessage != record.failureMessage {
                record.status = status
                record.failureMessage = fax.failureMessage
                record.updatedAt = .now
            }
        }
    }
}
