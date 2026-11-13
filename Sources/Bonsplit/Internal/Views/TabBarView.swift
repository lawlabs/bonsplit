import SwiftUI
import UniformTypeIdentifiers

/// Tab bar view with scrollable tabs, drag/drop support, and split buttons
struct TabBarView: View {
    @Environment(BonsplitController.self) private var controller
    @Environment(SplitViewController.self) private var splitViewController
    
    @Bindable var pane: PaneState
    let isFocused: Bool
    var showSplitButtons: Bool = true

    @State private var dropTargetIndex: Int?
    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var canScrollLeft: Bool {
        scrollOffset > 1
    }

    private var canScrollRight: Bool {
        contentWidth > containerWidth && scrollOffset < contentWidth - containerWidth - 1
    }

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tabs with fade overlays
            GeometryReader { containerGeo in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TabBarMetrics.tabSpacing) {
                            ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { index, tab in
                                tabItem(for: tab, at: index)
                                    .id(tab.id)
                            }

                            // Drop zone at end of tabs
                            dropZoneAtEnd
                        }
                        .padding(.horizontal, TabBarMetrics.barPadding)
                        .background(
                            GeometryReader { contentGeo in
                                Color.clear
                                    .onChange(of: contentGeo.frame(in: .named("tabScroll"))) { _, newFrame in
                                        scrollOffset = -newFrame.minX
                                        contentWidth = newFrame.width
                                    }
                                    .onAppear {
                                        let frame = contentGeo.frame(in: .named("tabScroll"))
                                        scrollOffset = -frame.minX
                                        contentWidth = frame.width
                                    }
                            }
                        )
                    }
                    .coordinateSpace(name: "tabScroll")
                    .onAppear {
                        containerWidth = containerGeo.size.width
                        if let tabId = pane.selectedTabId {
                            proxy.scrollTo(tabId, anchor: .center)
                        }
                    }
                    .onChange(of: containerGeo.size.width) { _, newWidth in
                        containerWidth = newWidth
                    }
                    .onChange(of: pane.selectedTabId) { _, newTabId in
                        if let tabId = newTabId {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(tabId, anchor: .center)
                            }
                        }
                    }
                }
                .frame(height: TabBarMetrics.barHeight)
                .overlay(fadeOverlays)
            }

            Spacer()

            // Split buttons
            if showSplitButtons {
                splitButtons
            }
        }
        .frame(height: TabBarMetrics.barHeight)
        .contentShape(Rectangle())
        .background(tabBarBackground)
        .saturation(isFocused ? 1.0 : 0)
    }

    // MARK: - Tab Item

    @ViewBuilder
    private func tabItem(for tab: TabItem, at index: Int) -> some View {
        TabItemView(
            tab: tab,
            isSelected: pane.selectedTabId == tab.id,
            canClose: controller.configuration.allowCloseTabs,
            onSelect: {
                withAnimation(.easeInOut(duration: TabBarMetrics.selectionDuration)) {
                    controller.selectTab(TabID(id: tab.id))
                }
            },
            onClose: {
                withAnimation(.easeInOut(duration: TabBarMetrics.closeDuration)) {
                    _ = controller.closeTab(TabID(id: tab.id), inPane: pane.id)
                }
            }
        )
        .onDrag {
            createItemProvider(for: tab)
        } preview: {
            TabDragPreview(tab: tab)
        }
        .onDrop(of: [TabDragProvider.contentType], delegate: TabDropDelegate(
            targetIndex: index,
            paneId: pane.id,
            controller: controller,
            dropTargetIndex: $dropTargetIndex
        ))
        .overlay(alignment: .leading) {
            if dropTargetIndex == index {
                dropIndicator
            }
        }
    }

    // MARK: - Item Provider

    private func createItemProvider(for tab: TabItem) -> NSItemProvider {
        let transfer = TabTransferData(tabId: TabID(id: tab.id), sourcePaneId: pane.id)
        splitViewController.tabDrag = transfer

        return TabDragProvider.make(for: transfer)
    }

    // MARK: - Drop Zone at End

    @ViewBuilder
    private var dropZoneAtEnd: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 30, height: TabBarMetrics.tabHeight)
            .contentShape(Rectangle())
            .onDrop(of: [TabDragProvider.contentType], delegate: TabDropDelegate(
                targetIndex: pane.tabs.count,
                paneId: pane.id,
                controller: controller,
                dropTargetIndex: $dropTargetIndex
            ))
            .overlay(alignment: .leading) {
                if dropTargetIndex == pane.tabs.count {
                    dropIndicator
                }
            }
    }

    // MARK: - Drop Indicator

    @ViewBuilder
    private var dropIndicator: some View {
        Capsule()
            .fill(TabBarColors.dropIndicator)
            .frame(width: TabBarMetrics.dropIndicatorWidth, height: TabBarMetrics.dropIndicatorHeight)
            .offset(x: -1)
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Split Buttons

    @ViewBuilder
    private var splitButtons: some View {
        HStack(spacing: 4) {
            Button {
                // 120fps animation handled by SplitAnimator
                controller.splitPane(pane.id, orientation: .horizontal)
            } label: {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Split Right")

            Button {
                // 120fps animation handled by SplitAnimator
                controller.splitPane(pane.id, orientation: .vertical)
            } label: {
                Image(systemName: "square.split.1x2")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Split Down")
        }
        .padding(.trailing, 8)
    }

    // MARK: - Fade Overlays

    @ViewBuilder
    private var fadeOverlays: some View {
        let fadeWidth: CGFloat = 24

        HStack(spacing: 0) {
            // Left fade
            LinearGradient(
                colors: [TabBarColors.barBackground, TabBarColors.barBackground.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
            .opacity(canScrollLeft ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: canScrollLeft)
            .allowsHitTesting(false)

            Spacer()

            // Right fade
            LinearGradient(
                colors: [TabBarColors.barBackground.opacity(0), TabBarColors.barBackground],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
            .opacity(canScrollRight ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: canScrollRight)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var tabBarBackground: some View {
        Rectangle()
            .fill(isFocused ? TabBarColors.barBackground : TabBarColors.barBackground.opacity(0.95))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TabBarColors.separator)
                    .frame(height: 1)
            }
    }
}

// MARK: - Tab Drop Delegate

struct TabDropDelegate: DropDelegate {
    let targetIndex: Int
    let paneId: PaneID
    let controller: BonsplitController
    @Binding var dropTargetIndex: Int?

    func performDrop(info: DropInfo) -> Bool {
        dropTargetIndex = nil
        guard controller.canDropTab(into: paneId) else { return false }
        return TabDragProvider.load(from: info) { transfer in
            withAnimation(.spring(duration: TabBarMetrics.reorderDuration, bounce: TabBarMetrics.reorderBounce)) {
                controller.dropTab(transfer, into: paneId, at: targetIndex)
            }
        }
    }

    func dropEntered(info: DropInfo) {
        dropTargetIndex = targetIndex
    }

    func dropExited(info: DropInfo) {
        if dropTargetIndex == targetIndex {
            dropTargetIndex = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: controller.canDropTab(into: paneId) ? .move : .forbidden)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [TabDragProvider.contentType]) && controller.canDropTab(into: paneId)
    }
}
