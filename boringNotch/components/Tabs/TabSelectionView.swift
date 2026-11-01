//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    var id: NotchViews { view }
    let label: String
    let icon: String
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.showHomeTab) private var showHomeTab
    @Default(.showShelfTab) private var showShelfTab
    @Default(.showTimerTab) private var showTimerTab
    @Default(.showAITab) private var showAITab
    @Default(.boringShelf) private var shelfEnabled
    @Default(.topBarSlots) private var topBarSlots
    @Namespace var animation
    @State private var dragOffset: CGFloat = 0

    private var visibleTabs: [TabModel] {
        TopBarTab.orderedVisibleTabs(
            slots: topBarSlots,
            showHome: showHomeTab,
            showShelf: showShelfTab,
            showTimer: showTimerTab,
            showAI: showAITab,
            shelfEnabled: shelfEnabled
        )
        .map { tab in
            TabModel(label: tab.label, icon: tab.iconName, view: tab.notchView)
        }
    }

    private var visibleViewKey: String {
        visibleTabs.map { String(describing: $0.view) }.joined(separator: ",")
    }

    func switchTab(by offset: Int) {
        guard let currentIndex = visibleTabs.firstIndex(where: { $0.view == coordinator.currentView }) else { return }
        let newIndex = currentIndex + offset
        if newIndex >= 0 && newIndex < visibleTabs.count {
            withAnimation(.smooth) {
                coordinator.currentView = visibleTabs[newIndex].view
            }
        }
    }

    var body: some View {
        Group {
            if visibleTabs.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: 0) {
                    ForEach(visibleTabs) { tab in
                        TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                            withAnimation(.smooth) {
                                coordinator.currentView = tab.view
                            }
                        }
                        .frame(height: 26)
                        .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                        .background {
                            if tab.view == coordinator.currentView {
                                Capsule()
                                    .fill(Color(nsColor: .secondarySystemFill))
                                    .matchedGeometryEffect(id: "capsule", in: animation)
                            }
                        }
                    }
                }
                .clipShape(Capsule())
                .offset(x: dragOffset * 0.04)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            if value.translation.width < -40 {
                                switchTab(by: 1)
                            } else if value.translation.width > 40 {
                                switchTab(by: -1)
                            }
                            withAnimation(.snappy) { dragOffset = 0 }
                        }
                )
            }
        }
        .onAppear(perform: ensureCurrentViewVisible)
        .onChange(of: visibleViewKey) { _, _ in
            ensureCurrentViewVisible()
        }
    }

    /// Keeps the notch from showing a tab that the user just disabled.
    private func ensureCurrentViewVisible() {
        let views = visibleTabs.map(\.view)
        guard !views.isEmpty else { return }
        guard !views.contains(coordinator.currentView) else { return }
        withAnimation(.smooth) {
            coordinator.currentView = views[0]
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
