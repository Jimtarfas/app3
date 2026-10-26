import Foundation
import SwiftData

enum FaxStatus: String, Codable {
    case queued, sending, delivered, failed

    var isFinal: Bool { self == .delivered || self == .failed }

    var title: String {
        switch self {
        case .queued: "Queued"
        case .sending: "Sending"
        case .delivered: "Delivered"
        case .failed: "Failed"
        }
    }

    var symbol: String {
        switch self {
        case .queued: "clock"
        case .sending: "paperplane"
        case .delivered: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

@Model
final class FaxRecord {
    @Attribute(.unique) var id: UUID
    var serverID: String
    var recipientName: String
    var faxNumber: String
    var pageCount: Int
    var statusRaw: String
    var failureMessage: String?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), serverID: String, recipientName: String, faxNumber: String, pageCount: Int,
         status: FaxStatus, createdAt: Date = .now) {
        self.id = id
        self.serverID = serverID
        self.recipientName = recipientName
        self.faxNumber = faxNumber
        self.pageCount = pageCount
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var status: FaxStatus {
        get { FaxStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    var displayName: String {
        recipientName.isEmpty ? PhoneFormatter.display(faxNumber) : recipientName
    }

    /// The PDF that was sent, kept on the device so it can be viewed, shared or resent.
    var documentURL: URL { FaxRecord.documentsFolder.appendingPathComponent("\(id.uuidString).pdf") }

    static var documentsFolder: URL {
        let url = URL.applicationSupportDirectory.appendingPathComponent("Faxes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
