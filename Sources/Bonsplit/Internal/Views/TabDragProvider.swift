import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum TabDragProvider {
    // Use an existing data type so host apps need no Info.plist declaration.
    static let contentType = UTType.json

    static func make(for transfer: TabTransferData) -> NSItemProvider {
        let provider = NSItemProvider()
        if let data = try? JSONEncoder().encode(transfer) {
            provider.registerDataRepresentation(for: contentType, visibility: .ownProcess) { completion in
                completion(data, nil)
                return nil
            }
        }
        return provider
    }

    static func load(from info: DropInfo, completion: @escaping @MainActor @Sendable (TabTransferData) -> Void) -> Bool {
        guard let provider = info.itemProviders(for: [contentType]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: contentType.identifier) { data, _ in
            guard let data, let transfer = try? JSONDecoder().decode(TabTransferData.self, from: data) else { return }
            DispatchQueue.main.async { completion(transfer) }
        }
        return true
    }
}
