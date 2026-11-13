import Foundation

/// Represents a single tab in a pane's tab bar (internal representation)
struct TabItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var icon: String?
    var isDirty: Bool

    init(
        id: UUID = UUID(),
        title: String,
        icon: String? = "doc.text",
        isDirty: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isDirty = isDirty
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Identifies a single drag. Tab metadata stays in the source pane.
struct TabTransferData: Codable, Equatable, Sendable {
    let token: UUID
    let tabId: TabID
    let sourcePaneId: PaneID

    init(tabId: TabID, sourcePaneId: PaneID) {
        self.token = UUID()
        self.tabId = tabId
        self.sourcePaneId = sourcePaneId
    }
}
