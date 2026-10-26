import Foundation

struct CoverSheet: Equatable {
    var fromName = ""
    var fromCompany = ""
    var fromPhone = ""
    var fromFax = ""
    var fromEmail = ""
    var toName = ""
    var toCompany = ""
    var toFax = ""
    var toPhone = ""
    var subject = ""
    var message = ""
    var date = Date.now
    var urgent = false
    var forReview = false
    var pleaseComment = false
    var pleaseReply = false
    var confidential = true

    /// A cover sheet pre-filled with the sender details saved in Settings.
    static func withSavedSender() -> CoverSheet {
        let defaults = UserDefaults.standard
        var sheet = CoverSheet()
        sheet.fromName = defaults.string(forKey: SenderKeys.name) ?? ""
        sheet.fromCompany = defaults.string(forKey: SenderKeys.company) ?? ""
        sheet.fromPhone = defaults.string(forKey: SenderKeys.phone) ?? ""
        sheet.fromFax = defaults.string(forKey: SenderKeys.fax) ?? ""
        sheet.fromEmail = defaults.string(forKey: SenderKeys.email) ?? ""
        return sheet
    }
}

enum SenderKeys {
    static let name = "sender.name"
    static let company = "sender.company"
    static let phone = "sender.phone"
    static let fax = "sender.fax"
    static let email = "sender.email"
}
