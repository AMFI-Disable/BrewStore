import Foundation

struct BrewStoreOperationRecord: Identifiable, Hashable, Codable {
    let id: UUID
    let date: Date
    let title: String
    let succeeded: Bool
    let detail: String

    init(id: UUID = UUID(), date: Date, title: String, succeeded: Bool, detail: String) {
        self.id = id
        self.date = date
        self.title = title
        self.succeeded = succeeded
        self.detail = detail
    }
}
