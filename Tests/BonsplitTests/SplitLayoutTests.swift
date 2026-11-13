import AppKit
import SwiftUI
import XCTest
@testable import Bonsplit

final class SplitLayoutTests: XCTestCase {
    @MainActor
    func testSplitWaitsForAUsableSizeAndKeepsBothPanesVisible() async throws {
        let controller = BonsplitController()
        XCTAssertNotNil(controller.splitPane(orientation: .horizontal))
        let state = try XCTUnwrap(controller.internalController.allSplits.first)
        let split = LayoutAwareSplitView(frame: .zero)
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(NSView())
        split.addArrangedSubview(NSView())

        let positioned = expectation(description: "Initial divider position applied")
        let coordinator = SplitContainerView<Text, Text>.Coordinator(
            splitState: state, minimumPaneSize: 100, onGeometryChange: { _ in positioned.fulfill() }
        )
        split.delegate = coordinator
        split.onLayout = { [weak split] in
            guard let split else { return }
            coordinator.applyInitialPosition(in: split, animator: controller.internalController.animator, duration: 0)
        }
        split.layout()

        XCTAssertNotNil(split.onLayout)
        XCTAssertNotNil(state.animationOrigin)
        XCTAssertTrue(split.arrangedSubviews.allSatisfy { !$0.isHidden })

        split.setFrameSize(NSSize(width: 400, height: 300))
        split.layout()
        await fulfillment(of: [positioned], timeout: 2)

        XCTAssertNil(split.onLayout)
        XCTAssertNil(state.animationOrigin)
        XCTAssertEqual(state.dividerPosition, 0.5)
        XCTAssertTrue(split.arrangedSubviews.allSatisfy { !$0.isHidden && $0.frame.width > 100 })
    }

    @MainActor
    func testNarrowContentKeepsCenterAndVerticalDropZonesReachable() throws {
        let controller = BonsplitController()
        let pane = try XCTUnwrap(controller.focusedPaneId)
        let delegate = UnifiedPaneDropDelegate(
            size: CGSize(width: 150, height: 120),
            paneId: pane,
            controller: controller,
            activeDropZone: .constant(nil)
        )

        XCTAssertEqual(delegate.zoneForLocation(CGPoint(x: 20, y: 10)), .left)
        XCTAssertEqual(delegate.zoneForLocation(CGPoint(x: 140, y: 110)), .right)
        XCTAssertEqual(delegate.zoneForLocation(CGPoint(x: 75, y: 10)), .top)
        XCTAssertEqual(delegate.zoneForLocation(CGPoint(x: 75, y: 110)), .bottom)
        XCTAssertEqual(delegate.zoneForLocation(CGPoint(x: 75, y: 60)), .center)
    }

    @MainActor
    func testDropPreviewMatchesTheAllowedOperation() throws {
        let controller = BonsplitController()
        let source = try XCTUnwrap(controller.focusedPaneId)
        let destination = try XCTUnwrap(controller.splitPane(orientation: .horizontal))
        let tab = try XCTUnwrap(controller.createTab(title: "Only tab", inPane: destination))
        controller.internalController.tabDrag = TabTransferData(tabId: tab, sourcePaneId: destination)
        let ownPaneDrop = UnifiedPaneDropDelegate(
            size: CGSize(width: 400, height: 300), paneId: destination,
            controller: controller, activeDropZone: .constant(nil)
        )
        let otherPaneDrop = UnifiedPaneDropDelegate(
            size: CGSize(width: 400, height: 300), paneId: source,
            controller: controller, activeDropZone: .constant(nil)
        )
        let edge = CGPoint(x: 380, y: 150)

        XCTAssertNil(ownPaneDrop.allowedZone(at: edge))
        XCTAssertEqual(otherPaneDrop.allowedZone(at: edge), .right)
        controller.configuration.allowSplits = false
        XCTAssertEqual(otherPaneDrop.allowedZone(at: edge), .center)
        controller.configuration.allowCrossPaneTabMove = false
        XCTAssertNil(otherPaneDrop.allowedZone(at: edge))
    }
}
