import SwiftUI
import AppKit

/// A new split can be mounted before SwiftUI gives it a usable frame.
final class LayoutAwareSplitView: NSSplitView {
    var onLayout: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    // Pane content adapts to the space allocated by the parent layout.
    override var fittingSize: NSSize {
        .zero
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// SwiftUI wrapper around NSSplitView for native split behavior
struct SplitContainerView<Content: View, EmptyContent: View>: NSViewRepresentable {
    @Bindable var splitState: SplitState
    let controller: SplitViewController
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch
    var appearance: BonsplitConfiguration.Appearance = .default
    /// Callback when geometry changes. Bool indicates if change is during active divider drag.
    var onGeometryChange: ((_ isDragging: Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(splitState: splitState, minimumPaneSize: minimumPaneSize, onGeometryChange: onGeometryChange)
    }

    private var minimumPaneSize: CGFloat {
        splitState.orientation == .horizontal ? appearance.minimumPaneWidth : appearance.minimumPaneHeight
    }

    func makeNSView(context: Context) -> LayoutAwareSplitView {
        let splitView = LayoutAwareSplitView()
        splitView.isVertical = splitState.orientation == .horizontal
        splitView.dividerStyle = .thin
        let coordinator = context.coordinator
        splitView.delegate = coordinator

        // First child
        let firstHosting = makeHostingView(for: splitState.first)
        splitView.addArrangedSubview(firstHosting)

        // Second child
        let secondHosting = makeHostingView(for: splitState.second)
        splitView.addArrangedSubview(secondHosting)

        configureInitialLayout(of: splitView, coordinator: coordinator)
        return splitView
    }

    private func configureInitialLayout(of splitView: LayoutAwareSplitView, coordinator: Coordinator) {
        let animator = controller.animator
        let duration = appearance.enableAnimations ? appearance.animationDuration : 0
        splitView.onLayout = { [weak splitView, weak coordinator] in
            guard let splitView, let coordinator else { return }
            coordinator.applyInitialPosition(in: splitView, animator: animator, duration: duration)
        }
        splitView.needsLayout = true
    }

    func updateNSView(_ splitView: LayoutAwareSplitView, context: Context) {
        // Update orientation if changed
        splitView.isVertical = splitState.orientation == .horizontal

        // Update children
        let subviews = splitView.arrangedSubviews
        if subviews.count >= 2 {
            updateHostingView(subviews[0], for: splitState.first)
            updateHostingView(subviews[1], for: splitState.second)
        }

        let coordinator = context.coordinator
        let minimumChanged = coordinator.minimumPaneSize != minimumPaneSize
        coordinator.minimumPaneSize = minimumPaneSize
        coordinator.onGeometryChange = onGeometryChange
        if splitView.onLayout != nil {
            configureInitialLayout(of: splitView, coordinator: coordinator)
        }
        coordinator.syncPosition(splitState.dividerPosition, in: splitView, force: minimumChanged)
    }

    // MARK: - Helpers

    private func makeHostingView(for node: SplitNode) -> NSView {
        let hostingController = NSHostingController(rootView: AnyView(makeView(for: node)))
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        return hostingController.view
    }

    private func updateHostingView(_ view: NSView, for node: SplitNode) {
        // Find the hosting controller's view and update it
        if let hostingView = view as? NSHostingView<AnyView> {
            hostingView.rootView = AnyView(makeView(for: node))
        }
    }

    @ViewBuilder
    private func makeView(for node: SplitNode) -> some View {
        switch node {
        case .pane(let paneState):
            PaneContainerView(
                pane: paneState,
                controller: controller,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle
            )
        case .split(let nestedSplitState):
            SplitContainerView(
                splitState: nestedSplitState,
                controller: controller,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle,
                appearance: appearance,
                onGeometryChange: onGeometryChange
            )
            .id(nestedSplitState.id)
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSSplitViewDelegate {
        let splitState: SplitState
        var minimumPaneSize: CGFloat
        private var hasInitialPosition = false
        var isAnimating = false
        var onGeometryChange: ((_ isDragging: Bool) -> Void)?
        /// Track last applied position to detect external changes
        var lastAppliedPosition: CGFloat = 0.5
        /// Track if user is actively dragging the divider
        var isDragging = false

        init(splitState: SplitState, minimumPaneSize: CGFloat, onGeometryChange: ((_ isDragging: Bool) -> Void)?) {
            self.splitState = splitState
            self.minimumPaneSize = minimumPaneSize
            self.onGeometryChange = onGeometryChange
            self.lastAppliedPosition = splitState.dividerPosition
        }

        func applyInitialPosition(in splitView: LayoutAwareSplitView, animator: SplitAnimator, duration: TimeInterval) {
            let size = splitSize(splitView)
            guard !hasInitialPosition, size > splitView.dividerThickness else { return }
            hasInitialPosition = true
            splitView.onLayout = nil

            let target = dividerCoordinate(for: splitState.dividerPosition, in: splitView)
            let origin = splitState.animationOrigin
            isAnimating = true

            // Layout can run while SwiftUI is updating. Publish model changes on the next turn.
            DispatchQueue.main.async { [weak self, weak splitView] in
                guard let self, let splitView else { return }
                self.splitState.animationOrigin = nil
                let currentSize = self.splitSize(splitView)
                let end = self.dividerCoordinate(for: self.splitState.dividerPosition, in: splitView)
                if let origin, duration.isFinite, duration > 0,
                   currentSize > splitView.dividerThickness, splitView.window != nil,
                   !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    let start = origin == .fromFirst ? 0 : currentSize - splitView.dividerThickness
                    animator.animate(splitView: splitView, from: start, to: end, duration: duration) { [weak self, weak splitView] in
                        guard let self, let splitView else { return }
                        self.finishInitialPosition(in: splitView)
                    }
                } else {
                    self.finishInitialPosition(in: splitView)
                }
            }

            splitView.setPosition(target, ofDividerAt: 0)
        }

        private func finishInitialPosition(in splitView: NSSplitView) {
            // Re-read the requested position and bounds after an animated layout or window resize.
            splitView.setPosition(dividerCoordinate(for: splitState.dividerPosition, in: splitView), ofDividerAt: 0)
            lastAppliedPosition = splitState.dividerPosition
            isAnimating = false
            onGeometryChange?(false)
        }

        private func splitSize(_ splitView: NSSplitView) -> CGFloat {
            splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        }

        private func effectiveMinimum(in splitView: NSSplitView) -> CGFloat {
            let available = max(0, splitSize(splitView) - splitView.dividerThickness)
            return min(max(0, minimumPaneSize), available / 2)
        }

        private func dividerCoordinate(for ratio: CGFloat, in splitView: NSSplitView) -> CGFloat {
            let size = splitSize(splitView)
            let minimum = effectiveMinimum(in: splitView)
            return max(minimum, min(size * ratio, size - splitView.dividerThickness - minimum))
        }

        /// Apply external position changes to the NSSplitView
        func syncPosition(_ statePosition: CGFloat, in splitView: NSSplitView, force: Bool = false) {
            guard hasInitialPosition, !isAnimating else { return }

            if force || abs(statePosition - lastAppliedPosition) > 0.01 {
                guard splitSize(splitView) > splitView.dividerThickness else { return }
                splitView.setPosition(dividerCoordinate(for: statePosition, in: splitView), ofDividerAt: 0)
                splitView.layoutSubtreeIfNeeded()
                lastAppliedPosition = statePosition
            }
        }

        func splitViewWillResizeSubviews(_ notification: Notification) {
            // Detect if this is a user drag by checking mouse state
            if NSApp?.currentEvent?.type == .leftMouseDragged {
                isDragging = true
            }
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            // Skip position updates during animation
            guard hasInitialPosition, !isAnimating else { return }
            guard let splitView = notification.object as? NSSplitView else { return }

            let totalSize = splitSize(splitView)

            guard totalSize > 0 else { return }

            if let firstSubview = splitView.arrangedSubviews.first {
                let dividerPosition = splitState.orientation == .horizontal
                    ? firstSubview.frame.width
                    : firstSubview.frame.height

                let normalizedPosition = dividerPosition / totalSize

                // Check if drag ended (mouse up)
                let wasDragging = isDragging
                if NSApp?.currentEvent?.type == .leftMouseUp {
                    isDragging = false
                }

                Task { @MainActor in
                    self.splitState.dividerPosition = normalizedPosition
                    self.lastAppliedPosition = normalizedPosition
                    // Notify geometry change with drag state
                    self.onGeometryChange?(wasDragging)
                }
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            // Allow edge positions during animation
            guard !isAnimating else { return proposedMinimumPosition }
            return max(proposedMinimumPosition, effectiveMinimum(in: splitView))
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            // Allow edge positions during animation
            guard !isAnimating else { return proposedMaximumPosition }
            let maximum = splitSize(splitView) - splitView.dividerThickness - effectiveMinimum(in: splitView)
            return min(proposedMaximumPosition, maximum)
        }
    }
}
