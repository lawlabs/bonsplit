import Foundation
import SwiftUI

/// Central controller managing the entire split view state (internal implementation)
@Observable
@MainActor
final class SplitViewController {
    /// The root node of the split tree
    var rootNode: SplitNode

    /// Currently focused pane ID
    var focusedPaneId: PaneID?

    /// The latest local drag. Starting another drag replaces it, and a matching drop consumes it.
    var tabDrag: TabTransferData?

    /// Current frame of the entire split view container
    var containerFrame: CGRect = .zero

    /// Flag to prevent notification loops during external updates
    var isExternalUpdateInProgress: Bool = false

    /// Timestamp of last geometry notification for debouncing
    var lastGeometryNotificationTime: TimeInterval = 0

    /// Callback for geometry changes
    var onGeometryChange: (() -> Void)?
    
    let animator: SplitAnimator = SplitAnimator()

    /// Currently zoomed pane ID (nil = not zoomed)
    var zoomedPaneId: PaneID?

    init(rootNode: SplitNode? = nil) {
        if let rootNode {
            self.rootNode = rootNode
        } else {
            // Initialize with a single pane containing a welcome tab
            let welcomeTab = TabItem(title: "Welcome", icon: "star")
            let initialPane = PaneState(tabs: [welcomeTab])
            self.rootNode = .pane(initialPane)
            self.focusedPaneId = initialPane.id
        }
    }

    // MARK: - Focus Management

    /// Set focus to a specific pane
    func focusPane(_ paneId: PaneID) {
        guard rootNode.findPane(paneId) != nil else { return }
        focusedPaneId = paneId
    }

    /// Get the currently focused pane state
    var focusedPane: PaneState? {
        guard let focusedPaneId else { return nil }
        return rootNode.findPane(focusedPaneId)
    }

    // MARK: - Zoom

    /// Toggle zoom on the specified pane (or the focused pane if nil).
    /// - Returns: `true` if the zoom state changed
    @discardableResult
    func toggleZoom(paneId: PaneID? = nil) -> Bool {
        let targetId = paneId ?? focusedPaneId
        guard let targetId else { return false }

        // If already zoomed
        if let currentZoomed = zoomedPaneId {
            if currentZoomed == targetId {
                // Toggle off
                zoomedPaneId = nil
                return true
            } else {
                // Move zoom to different pane
                guard rootNode.findPane(targetId) != nil else { return false }
                zoomedPaneId = targetId
                return true
            }
        }

        // Not zoomed — only zoom if there are multiple panes
        guard rootNode.allPaneIds.count > 1 else { return false }
        guard rootNode.findPane(targetId) != nil else { return false }

        zoomedPaneId = targetId
        return true
    }

    /// Explicitly exit zoom without toggling.
    func unzoom() {
        zoomedPaneId = nil
    }

    // MARK: - Split Operations

    /// Split the specified pane and return the new pane.
    @discardableResult
    func splitPane(
        _ paneId: PaneID,
        orientation: SplitOrientation,
        with newTab: TabItem? = nil,
        insertFirst: Bool = false
    ) -> PaneState? {
        let newPane = PaneState(tabs: newTab.map { [$0] } ?? [])
        guard let newRoot = insertingSplit(
            in: rootNode, at: paneId, orientation: orientation, newPane: newPane, insertFirst: insertFirst
        ) else { return nil }

        zoomedPaneId = nil
        rootNode = newRoot
        focusedPaneId = newPane.id
        return newPane
    }

    private func insertingSplit(
        in node: SplitNode,
        at paneId: PaneID,
        orientation: SplitOrientation,
        newPane: PaneState,
        insertFirst: Bool
    ) -> SplitNode? {
        switch node {
        case .pane(let pane):
            guard pane.id == paneId else { return nil }
            return .split(SplitState(
                orientation: orientation,
                first: insertFirst ? .pane(newPane) : node,
                second: insertFirst ? node : .pane(newPane),
                animationOrigin: insertFirst ? .fromFirst : .fromSecond
            ))
        case .split(let split):
            if let first = insertingSplit(
                in: split.first, at: paneId, orientation: orientation, newPane: newPane, insertFirst: insertFirst
            ) {
                split.first = first
            } else if let second = insertingSplit(
                in: split.second, at: paneId, orientation: orientation, newPane: newPane, insertFirst: insertFirst
            ) {
                split.second = second
            } else {
                return nil
            }
            return node
        }
    }

    /// Close a pane and collapse the split
    @discardableResult
    func closePane(_ paneId: PaneID, allowLastPane: Bool = false) -> Bool {
        if case .pane = rootNode {
            return allowLastPane && clearLastPane(paneId)
        }
        guard let result = closingPane(paneId, in: rootNode) else { return false }

        rootNode = result.node
        if focusedPaneId == paneId {
            focusedPaneId = result.sibling
        }

        // Clear zoom if zoomed pane was closed or tree collapsed to single pane
        if let zid = zoomedPaneId {
            if rootNode.findPane(zid) == nil || rootNode.allPaneIds.count <= 1 {
                zoomedPaneId = nil
            }
        }
        return true
    }

    /// Remove tabs from the last pane while keeping a place to open the next tab.
    private func clearLastPane(_ paneId: PaneID) -> Bool {
        guard case .pane(let pane) = rootNode, pane.id == paneId else { return false }
        let replacement = PaneState()
        rootNode = .pane(replacement)
        focusedPaneId = replacement.id
        zoomedPaneId = nil
        return true
    }

    private func closingPane(_ paneId: PaneID, in node: SplitNode) -> (node: SplitNode, sibling: PaneID?)? {
        guard case .split(let split) = node else { return nil }

        if case .pane(let first) = split.first, first.id == paneId {
            return (split.second, split.second.allPaneIds.first)
        }
        if case .pane(let second) = split.second, second.id == paneId {
            return (split.first, split.first.allPaneIds.first)
        }
        if let result = closingPane(paneId, in: split.first) {
            split.first = result.node
            return (node, result.sibling)
        }
        if let result = closingPane(paneId, in: split.second) {
            split.second = result.node
            return (node, result.sibling)
        }
        return nil
    }

    // MARK: - Tab Operations

    /// Add a tab to the focused pane (or specified pane)
    func addTab(_ tab: TabItem, toPane paneId: PaneID? = nil, atIndex index: Int? = nil) {
        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId,
              let pane = rootNode.findPane(targetPaneId) else { return }

        if let index {
            pane.insertTab(tab, at: index)
        } else {
            pane.addTab(tab)
        }
    }

    /// Move the current tab item into an existing destination.
    func moveTab(_ tabId: TabID, from source: PaneState, to destination: PaneState, at index: Int?) -> TabItem? {
        guard source.id != destination.id, let tab = source.removeTab(tabId.id) else { return nil }
        if let index {
            destination.insertTab(tab, at: index)
        } else {
            destination.addTab(tab)
        }
        focusedPaneId = destination.id
        return tab
    }

    // MARK: - Keyboard Navigation

    /// Navigate focus to an adjacent pane based on spatial position
    func navigateFocus(direction: NavigationDirection) {
        guard let currentPaneId = focusedPaneId else { return }

        let allPaneBounds = rootNode.computePaneBounds()
        guard let currentBounds = allPaneBounds.first(where: { $0.paneId == currentPaneId })?.bounds else { return }

        if let targetPaneId = findBestNeighbor(from: currentBounds, currentPaneId: currentPaneId,
                                               direction: direction, allPaneBounds: allPaneBounds) {
            focusPane(targetPaneId)
        }
        // No neighbor found = at edge, do nothing
    }

    private func findBestNeighbor(from currentBounds: CGRect, currentPaneId: PaneID,
                                  direction: NavigationDirection, allPaneBounds: [PaneBounds]) -> PaneID? {
        let epsilon: CGFloat = 0.001

        // Filter to panes in the target direction
        let candidates = allPaneBounds.filter { paneBounds in
            guard paneBounds.paneId != currentPaneId else { return false }
            let b = paneBounds.bounds
            switch direction {
            case .left:  return b.maxX <= currentBounds.minX + epsilon
            case .right: return b.minX >= currentBounds.maxX - epsilon
            case .up:    return b.maxY <= currentBounds.minY + epsilon
            case .down:  return b.minY >= currentBounds.maxY - epsilon
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Score by overlap (perpendicular axis) and distance
        let scored: [(PaneID, CGFloat, CGFloat)] = candidates.map { c in
            let overlap: CGFloat
            let distance: CGFloat

            switch direction {
            case .left, .right:
                // Vertical overlap for horizontal movement
                overlap = max(0, min(currentBounds.maxY, c.bounds.maxY) - max(currentBounds.minY, c.bounds.minY))
                distance = direction == .left ? (currentBounds.minX - c.bounds.maxX) : (c.bounds.minX - currentBounds.maxX)
            case .up, .down:
                // Horizontal overlap for vertical movement
                overlap = max(0, min(currentBounds.maxX, c.bounds.maxX) - max(currentBounds.minX, c.bounds.minX))
                distance = direction == .up ? (currentBounds.minY - c.bounds.maxY) : (c.bounds.minY - currentBounds.maxY)
            }

            return (c.paneId, overlap, distance)
        }

        // Sort: prefer more overlap, then closer distance
        let sorted = scored.sorted { a, b in
            if abs(a.1 - b.1) > epsilon { return a.1 > b.1 }
            return a.2 < b.2
        }

        return sorted.first?.0
    }

    /// Create a new tab in the focused pane
    func createNewTab() {
        guard let pane = focusedPane else { return }
        let count = pane.tabs.count + 1
        let newTab = TabItem(title: "Untitled \(count)", icon: "doc")
        pane.addTab(newTab)
    }

    /// Select the previous tab in the focused pane
    func selectPreviousTab() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId,
              let currentIndex = pane.tabs.firstIndex(where: { $0.id == selectedTabId }),
              !pane.tabs.isEmpty else { return }

        let newIndex = currentIndex > 0 ? currentIndex - 1 : pane.tabs.count - 1
        pane.selectTab(pane.tabs[newIndex].id)
    }

    /// Select the next tab in the focused pane
    func selectNextTab() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId,
              let currentIndex = pane.tabs.firstIndex(where: { $0.id == selectedTabId }),
              !pane.tabs.isEmpty else { return }

        let newIndex = currentIndex < pane.tabs.count - 1 ? currentIndex + 1 : 0
        pane.selectTab(pane.tabs[newIndex].id)
    }

    // MARK: - Split State Access

    /// Find a split state by its UUID
    func findSplit(_ splitId: UUID) -> SplitState? {
        return findSplitRecursively(in: rootNode, id: splitId)
    }

    private func findSplitRecursively(in node: SplitNode, id: UUID) -> SplitState? {
        switch node {
        case .pane:
            return nil
        case .split(let splitState):
            if splitState.id == id {
                return splitState
            }
            if let found = findSplitRecursively(in: splitState.first, id: id) {
                return found
            }
            return findSplitRecursively(in: splitState.second, id: id)
        }
    }

    /// Get all split states in the tree
    var allSplits: [SplitState] {
        return collectSplits(from: rootNode)
    }

    private func collectSplits(from node: SplitNode) -> [SplitState] {
        switch node {
        case .pane:
            return []
        case .split(let splitState):
            return [splitState] + collectSplits(from: splitState.first) + collectSplits(from: splitState.second)
        }
    }
}
