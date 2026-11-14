import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum TabDragProvider {
    // Use an existing data type so host apps need no Info.plist declaration.
    static let contentType = UTType.json

    static func make(for transfer: TabTransferData, onRelease: @escaping @MainActor @Sendable () -> Void) -> NSItemProvider {
        let provider = NSItemProvider()
        guard let data = try? JSONEncoder().encode(transfer) else {
            onRelease()
            return provider
        }
        // System copies of the provider also retain its representation.
        let registration = DragRepresentation(data: data, onRelease: onRelease)
        provider.registerDataRepresentation(for: contentType, visibility: .ownProcess) { completion in
            completion(registration.data, nil)
            return nil
        }
        return provider
    }

    private final class DragRepresentation: Sendable {
        let data: Data
        let onRelease: @MainActor @Sendable () -> Void

        init(data: Data, onRelease: @escaping @MainActor @Sendable () -> Void) {
            self.data = data
            self.onRelease = onRelease
        }

        deinit {
            DispatchQueue.main.async { [onRelease] in onRelease() }
        }
    }
}
