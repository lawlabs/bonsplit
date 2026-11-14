import XCTest
@testable import Bonsplit

final class TabDropTests: XCTestCase {
    @MainActor
    func testDroppingOnlyTabBesideItsOwnPaneKeepsTheLayout() throws {
        let controller = BonsplitController()
        let original = try XCTUnwrap(controller.focusedPaneId)
        let pane = try XCTUnwrap(controller.splitPane(orientation: .horizontal))
        let tab = try XCTUnwrap(controller.createTab(title: "Unsaved", isDirty: true))
        let events = RecordingDelegate()
        controller.delegate = events

        let transfer = startDrag(tab, from: pane, in: controller)
        XCTAssertFalse(controller.canDropTab(into: pane, splitting: true))
        controller.dropTab(transfer, beside: pane, orientation: .horizontal, insertFirst: false)

        XCTAssertEqual(controller.allPaneIds, [original, pane])
        XCTAssertEqual(controller.focusedPaneId, pane)
        XCTAssertEqual(controller.selectedTab(inPane: pane)?.id, tab)
        XCTAssertEqual(controller.tab(tab)?.isDirty, true)
        XCTAssertTrue(events.splits.isEmpty)
        XCTAssertTrue(events.moves.isEmpty)
    }

    @MainActor
    func testEdgeDropMovesTabBeforeNotifyingTheDelegate() throws {
        let controller = BonsplitController()
        let pane = try XCTUnwrap(controller.focusedPaneId)
        let tab = try XCTUnwrap(controller.createTab(title: "Document"))
        let events = RecordingDelegate()
        controller.delegate = events

        let transfer = startDrag(tab, from: pane, in: controller)
        controller.dropTab(transfer, beside: pane, orientation: .vertical, insertFirst: true)

        let newPane = try XCTUnwrap(controller.focusedPaneId)
        XCTAssertEqual(controller.allPaneIds, [newPane, pane])
        XCTAssertEqual(controller.tabs(inPane: newPane).map(\.id), [tab])
        XCTAssertEqual(controller.allTabIds.filter { $0 == tab }.count, 1)
        XCTAssertEqual(events.splits, [newPane])
        XCTAssertEqual(events.tabsAtSplit, [tab])
        XCTAssertEqual(events.moves.map(\.source), [pane])
        XCTAssertEqual(events.moves.map(\.destination), [newPane])
    }

    @MainActor
    func testMovingLastTabCollapsesItsPaneAndKeepsDestinationFocused() throws {
        let controller = BonsplitController()
        let destination = try XCTUnwrap(controller.focusedPaneId)
        let first = try XCTUnwrap(controller.createTab(title: "First"))
        let source = try XCTUnwrap(controller.splitPane(orientation: .horizontal))
        let sibling = try XCTUnwrap(controller.splitPane(source, orientation: .vertical))
        let tab = try XCTUnwrap(controller.createTab(title: "Moving", inPane: source))
        let events = RecordingDelegate()
        controller.delegate = events

        let transfer = startDrag(tab, from: source, in: controller)
        controller.updateTab(tab, title: "Updated", icon: "star", isDirty: true)
        controller.dropTab(transfer, into: destination, at: 1)

        XCTAssertEqual(controller.allPaneIds, [destination, sibling])
        XCTAssertEqual(controller.tabs(inPane: destination).dropFirst().map(\.id), [tab, first])
        XCTAssertEqual(controller.focusedPaneId, destination)
        XCTAssertEqual(controller.selectedTab(inPane: destination)?.id, tab)
        XCTAssertEqual(controller.tab(tab)?.title, "Updated")
        XCTAssertEqual(controller.tab(tab)?.icon, "star")
        XCTAssertEqual(controller.tab(tab)?.isDirty, true)
        XCTAssertEqual(events.moves.map(\.destination), [destination])
        XCTAssertEqual(events.closedPanes, [source])
    }

    @MainActor
    func testStaleAndRepeatedDropsCannotDuplicateATab() throws {
        let controller = BonsplitController()
        let source = try XCTUnwrap(controller.focusedPaneId)
        let tab = try XCTUnwrap(controller.createTab(title: "Document"))
        let target = try XCTUnwrap(controller.splitPane(orientation: .horizontal))
        let stale = startDrag(tab, from: source, in: controller)
        let active = startDrag(tab, from: source, in: controller)

        controller.dropTab(stale, into: target, at: nil)
        XCTAssertEqual(controller.internalController.tabDrag, active)
        XCTAssertTrue(controller.tabs(inPane: target).isEmpty)

        controller.dropTab(active, into: target, at: nil)
        controller.dropTab(active, into: target, at: nil)
        controller.internalController.tabDrag = active
        controller.dropTab(active, beside: target, orientation: .vertical, insertFirst: false)

        XCTAssertEqual(controller.allPaneIds, [source, target])
        XCTAssertEqual(controller.tabs(inPane: target).map(\.id), [tab])
        XCTAssertEqual(controller.allTabIds.filter { $0 == tab }.count, 1)
    }

    @MainActor
    func testClosedDestinationLeavesTheSourceTabIntact() throws {
        let controller = BonsplitController()
        let source = try XCTUnwrap(controller.focusedPaneId)
        let tab = try XCTUnwrap(controller.createTab(title: "Document"))
        let target = try XCTUnwrap(controller.splitPane(orientation: .horizontal))
        let transfer = startDrag(tab, from: source, in: controller)
        XCTAssertTrue(controller.closePane(target))

        controller.dropTab(transfer, beside: target, orientation: .horizontal, insertFirst: false)

        XCTAssertEqual(controller.allPaneIds, [source])
        XCTAssertEqual(controller.selectedTab(inPane: source)?.id, tab)
        XCTAssertNil(controller.createTab(title: "Missing", inPane: target))
        XCTAssertNil(controller.splitPane(target, orientation: .horizontal))
        XCTAssertFalse(controller.closePane(target))
    }

    @MainActor
    func testSplitRejectsAnExistingTabID() throws {
        let controller = BonsplitController()
        let source = try XCTUnwrap(controller.focusedPaneId)
        let id = try XCTUnwrap(controller.createTab(title: "Document"))
        let tab = try XCTUnwrap(controller.tab(id))

        XCTAssertNil(controller.splitPane(orientation: .horizontal, withTab: tab))
        XCTAssertEqual(controller.allPaneIds, [source])
        XCTAssertEqual(controller.allTabIds.filter { $0 == id }.count, 1)
        XCTAssertNotNil(controller.splitPane(orientation: .horizontal, withTab: Tab(title: "New tab")))
    }

    @MainActor
    func testDropHonorsConfigurationAndDelegateVeto() throws {
        let controller = BonsplitController()
        let source = try XCTUnwrap(controller.focusedPaneId)
        let tab = try XCTUnwrap(controller.createTab(title: "Document"))
        let target = try XCTUnwrap(controller.splitPane(orientation: .horizontal))
        let events = RecordingDelegate()
        controller.delegate = events
        controller.configuration = .readOnly

        controller.dropTab(startDrag(tab, from: source, in: controller), into: target, at: nil)
        controller.dropTab(startDrag(tab, from: source, in: controller), beside: target, orientation: .vertical, insertFirst: true)
        controller.dropTab(startDrag(tab, from: source, in: controller), into: source, at: 0)
        XCTAssertFalse(controller.closeTab(tab))
        XCTAssertEqual(controller.tabs(inPane: source).last?.id, tab)

        controller.configuration = .default
        events.allowSplit = false
        controller.dropTab(startDrag(tab, from: source, in: controller), beside: target, orientation: .vertical, insertFirst: true)

        XCTAssertEqual(controller.allPaneIds, [source, target])
        XCTAssertEqual(controller.selectedTab(inPane: source)?.id, tab)
        XCTAssertTrue(controller.tabs(inPane: target).isEmpty)
        XCTAssertTrue(events.moves.isEmpty)
        XCTAssertTrue(events.splits.isEmpty)
    }

    @MainActor
    func testAutoCloseCanBeDisabledAndVetoed() throws {
        let controller = BonsplitController(configuration: .init(autoCloseEmptyPanes: false))
        let first = try XCTUnwrap(controller.focusedPaneId)
        let second = try XCTUnwrap(controller.splitPane(orientation: .horizontal))
        let tab = try XCTUnwrap(controller.createTab(title: "Document"))
        let events = RecordingDelegate()
        controller.delegate = events

        controller.dropTab(startDrag(tab, from: second, in: controller), into: first, at: nil)
        XCTAssertEqual(controller.allPaneIds, [first, second])
        XCTAssertTrue(controller.tabs(inPane: second).isEmpty)

        controller.configuration.autoCloseEmptyPanes = true
        events.allowClose = false
        let tabToClose = try XCTUnwrap(controller.createTab(title: "Close", inPane: second))
        XCTAssertTrue(controller.closeTab(tabToClose))
        XCTAssertEqual(controller.allPaneIds, [first, second])
        XCTAssertTrue(controller.tabs(inPane: second).isEmpty)
        XCTAssertTrue(events.closedPanes.isEmpty)
    }

    @MainActor
    func testDragProviderRoundTripsTheActiveToken() async throws {
        let transfer = TabTransferData(tabId: TabID(), sourcePaneId: PaneID())
        let provider = TabDragProvider.make(for: transfer) {}
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            provider.loadDataRepresentation(forTypeIdentifier: TabDragProvider.contentType.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
        XCTAssertEqual(try JSONDecoder().decode(TabTransferData.self, from: data), transfer)
        XCTAssertFalse(provider.hasItemConformingToTypeIdentifier("public.text"))
    }

    @MainActor
    func testDragRemainsActiveWhileAProviderCopyExists() async {
        let ended = expectation(description: "Drag provider released")
        let controller = BonsplitController()
        let transfer = TabTransferData(tabId: TabID(), sourcePaneId: PaneID())
        controller.internalController.tabDrag = transfer
        var copy: NSItemProvider?
        autoreleasepool {
            let provider = TabDragProvider.make(for: transfer) {
                controller.internalController.tabDrag = nil
                ended.fulfill()
            }
            copy = provider.copy() as? NSItemProvider
        }
        await Task.yield()
        XCTAssertTrue(copy?.hasItemConformingToTypeIdentifier(TabDragProvider.contentType.identifier) == true)
        XCTAssertEqual(controller.internalController.tabDrag, transfer)

        copy = nil
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertNil(controller.internalController.tabDrag)
    }

    @MainActor
    func testAcceptedDropMovesTheTabAfterLoadingTheProvider() async throws {
        let controller = BonsplitController()
        let source = try XCTUnwrap(controller.focusedPaneId)
        let tab = try XCTUnwrap(controller.createTab(title: "Document"))
        let destination = try XCTUnwrap(controller.splitPane(orientation: .horizontal))
        let transfer = startDrag(tab, from: source, in: controller)
        let provider = TabDragProvider.make(for: transfer) {}
        let moved = expectation(description: "Tab transfer applied")

        XCTAssertTrue(controller.performTabDrop(from: provider) { received in
            controller.dropTab(received, into: destination, at: nil)
            moved.fulfill()
        })
        XCTAssertNil(controller.internalController.tabDrag)
        await fulfillment(of: [moved], timeout: 2)

        XCTAssertNil(controller.internalController.pendingTabDrop)
        XCTAssertEqual(controller.tabs(inPane: destination).map(\.id), [tab])
        XCTAssertEqual(controller.allTabIds.filter { $0 == tab }.count, 1)
    }

    @MainActor
    private func startDrag(_ tab: TabID, from pane: PaneID, in controller: BonsplitController) -> TabTransferData {
        let transfer = TabTransferData(tabId: tab, sourcePaneId: pane)
        controller.internalController.tabDrag = transfer
        return transfer
    }
}

private final class RecordingDelegate: BonsplitDelegate {
    var allowSplit = true
    var allowClose = true
    var splits: [PaneID] = []
    var tabsAtSplit: [TabID] = []
    var closedPanes: [PaneID] = []
    var moves: [(source: PaneID, destination: PaneID)] = []

    func splitTabBar(_ controller: BonsplitController, shouldSplitPane pane: PaneID, orientation: SplitOrientation) -> Bool {
        allowSplit
    }

    func splitTabBar(_ controller: BonsplitController, shouldClosePane pane: PaneID) -> Bool {
        allowClose
    }

    func splitTabBar(_ controller: BonsplitController, didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation) {
        splits.append(newPane)
        tabsAtSplit = MainActor.assumeIsolated { controller.tabs(inPane: newPane).map(\.id) }
    }

    func splitTabBar(_ controller: BonsplitController, didClosePane paneId: PaneID) {
        closedPanes.append(paneId)
    }

    func splitTabBar(_ controller: BonsplitController, didMoveTab tab: Tab, fromPane source: PaneID, toPane destination: PaneID) {
        moves.append((source, destination))
    }
}
