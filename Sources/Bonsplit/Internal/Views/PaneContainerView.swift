import SwiftUI

/// Drop zone positions for creating splits
enum DropZone: Equatable {
    case center
    case left
    case right
    case top
    case bottom

    var orientation: SplitOrientation? {
        switch self {
        case .left, .right: return .horizontal
        case .top, .bottom: return .vertical
        case .center: return nil
        }
    }

    var insertsFirst: Bool {
        switch self {
        case .left, .top: return true
        default: return false
        }
    }
}

/// Container for a single pane with its tab bar and content area
struct PaneContainerView<Content: View, EmptyContent: View>: View {
    @Environment(BonsplitController.self) private var bonsplit
    @Bindable var pane: PaneState
    let controller: SplitViewController
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    @State private var activeDropZone: DropZone?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFocused: Bool {
        controller.focusedPaneId == pane.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            TabBarView(
                pane: pane,
                isFocused: isFocused,
                showSplitButtons: showSplitButtons
            )

            // Content area with drop zones
            contentAreaWithDropZones
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Content Area with Drop Zones

    @ViewBuilder
    private var contentAreaWithDropZones: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let dropTarget = UnifiedPaneDropDelegate(
                size: size,
                paneId: pane.id,
                controller: bonsplit,
                activeDropZone: $activeDropZone
            )

            ZStack {
                contentArea
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        bonsplit.focusPane(pane.id)
                    })

                if controller.tabDrag != nil {
                    // Give the entire pane a destination independent of the editor it hosts.
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .frame(width: size.width, height: size.height)
                        .onDrop(of: [TabDragProvider.contentType], delegate: dropTarget)
                        .accessibilityHidden(true)
                }

                // Visual placeholder (non-interactive)
                dropPlaceholder(for: activeDropZone, in: size)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(width: size.width, height: size.height)
        }
        .clipped()
        .onChange(of: controller.tabDrag) { _, transfer in
            if transfer == nil { activeDropZone = nil }
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if pane.tabs.isEmpty {
            emptyPaneView
        } else {
            switch contentViewLifecycle {
            case .recreateOnSwitch:
                // Original behavior: only render selected tab
                if let selectedTab = pane.selectedTab {
                    contentBuilder(selectedTab, pane.id)
                        .id(selectedTab.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

            case .keepAllAlive:
                // macOS-like behavior: keep all tab views in hierarchy
                ZStack {
                    ForEach(pane.tabs) { tab in
                        contentBuilder(tab, pane.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(tab.id == pane.selectedTabId ? 1 : 0)
                            .allowsHitTesting(tab.id == pane.selectedTabId)
                            .accessibilityHidden(tab.id != pane.selectedTabId)
                    }
                }
            }
        }
    }

    // MARK: - Drop Placeholder

    @ViewBuilder
    private func dropPlaceholder(for zone: DropZone?, in size: CGSize) -> some View {
        let placeholderColor = Color.accentColor.opacity(0.25)
        let borderColor = Color.accentColor
        let padding: CGFloat = 4
        let animate = bonsplit.configuration.appearance.enableAnimations && !reduceMotion

        // Calculate frame based on zone
        let frame: CGRect = {
            switch zone {
            case .center, .none:
                return CGRect(x: padding, y: padding, width: size.width - padding * 2, height: size.height - padding * 2)
            case .left:
                return CGRect(x: padding, y: padding, width: size.width / 2 - padding, height: size.height - padding * 2)
            case .right:
                return CGRect(x: size.width / 2, y: padding, width: size.width / 2 - padding, height: size.height - padding * 2)
            case .top:
                return CGRect(x: padding, y: padding, width: size.width - padding * 2, height: size.height / 2 - padding)
            case .bottom:
                return CGRect(x: padding, y: size.height / 2, width: size.width - padding * 2, height: size.height / 2 - padding)
            }
        }()

        let width = max(0, frame.size.width)
        let height = max(0, frame.size.height)
        RoundedRectangle(cornerRadius: 8)
            .fill(placeholderColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 2)
            )
            .frame(width: width, height: height)
            .position(x: frame.origin.x + width / 2, y: frame.origin.y + height / 2)
            .opacity(zone != nil ? 1 : 0)
            .animation(animate ? .easeOut(duration: 0.12) : nil, value: zone)
    }

    // MARK: - Empty Pane View

    @ViewBuilder
    private var emptyPaneView: some View {
        emptyPaneBuilder(pane.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Unified Pane Drop Delegate

struct UnifiedPaneDropDelegate: DropDelegate {
    let size: CGSize
    let paneId: PaneID
    let controller: BonsplitController
    @Binding var activeDropZone: DropZone?

    // Calculate zone based on position within the view
    func zoneForLocation(_ location: CGPoint) -> DropZone {
        let horizontalEdge = size.width * 0.25
        let verticalEdge = size.height * 0.25

        // Check edges first (left/right take priority at corners)
        if location.x < horizontalEdge {
            return .left
        } else if location.x > size.width - horizontalEdge {
            return .right
        } else if location.y < verticalEdge {
            return .top
        } else if location.y > size.height - verticalEdge {
            return .bottom
        } else {
            return .center
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let zone = allowedZone(at: info.location)
        activeDropZone = nil
        guard let zone else { return false }

        return controller.performTabDrop(info) { transfer in
            if let orientation = zone.orientation {
                controller.dropTab(transfer, beside: paneId, orientation: orientation, insertFirst: zone.insertsFirst)
                return
            }
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                controller.dropTab(transfer, into: paneId, at: nil)
            }
        }
    }

    func dropEntered(info: DropInfo) {
        activeDropZone = allowedZone(at: info.location)
    }

    func dropExited(info: DropInfo) {
        activeDropZone = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        activeDropZone = allowedZone(at: info.location)
        return DropProposal(operation: activeDropZone == nil ? .forbidden : .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        controller.internalController.tabDrag != nil
            && info.hasItemsConforming(to: [TabDragProvider.contentType])
    }

    func allowedZone(at location: CGPoint) -> DropZone? {
        guard CGRect(origin: .zero, size: size).contains(location) else { return nil }
        let zone = zoneForLocation(location)
        if zone != .center {
            if controller.canDropTab(into: paneId, splitting: true) { return zone }
            // With splits disabled, the content area still accepts moves between panes.
            guard !controller.configuration.allowSplits,
                  controller.internalController.tabDrag?.sourcePaneId != paneId else { return nil }
        }
        return controller.canDropTab(into: paneId) ? .center : nil
    }
}
