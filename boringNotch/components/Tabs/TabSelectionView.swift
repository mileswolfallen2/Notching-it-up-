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
    @Default(.showWeatherTab) private var showWeatherTab
    @Default(.showShelfTab) private var showShelfTab
    @Default(.showTimerTab) private var showTimerTab
    @Default(.showNotesTab) private var showNotesTab
    @Default(.showAITab) private var showAITab
    @Default(.showDevicesTab) private var showDevicesTab
    @Default(.boringShelf) private var shelfEnabled
    @Default(.topBarSlots) private var topBarSlots
    @Namespace var animation
    @State private var dragOffset: CGFloat = 0

    private var visibleTabs: [TabModel] {
        TopBarTab.orderedVisibleTabs(
            slots: topBarSlots,
            showHome: showHomeTab,
            showWeather: showWeatherTab,
            showShelf: showShelfTab,
            showTimer: showTimerTab,
            showNotes: showNotesTab,
            showAI: showAITab,
            showDevices: showDevicesTab,
            shelfEnabled: shelfEnabled
        )
        .map { tab in
            TabModel(label: tab.label, icon: tab.iconName, view: tab.notchView)
        }
    }

    private var visibleViewKey: String {
        visibleTabs.map { String(describing: $0.view) }.joined(separator: ",")
    }

    /// Collapse the tab strip before it can run into the physical notch.
    private var tabButtonPadding: CGFloat {
        switch visibleTabs.count {
        case 0...3: return 15
        case 4:     return 10
        default:    return 7
        }
    }

    func switchTab(by offset: Int) {
        coordinator.switchTab(by: offset)
    }

    var body: some View {
        Group {
            if visibleTabs.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: 0) {
                    ForEach(visibleTabs) { tab in
                        TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view, horizontalPadding: tabButtonPadding) {
                            withAnimation(BoringMotion.animation(.smooth)) {
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
                        .focusable()
                        .accessibilityHint("Switches the notch to the \(tab.label) tab")
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
                            withAnimation(BoringMotion.animation(.snappy)) { dragOffset = 0 }
                        }
                )
                .onKeyPress(.leftArrow) {
                    switchTab(by: -1)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    switchTab(by: 1)
                    return .handled
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Notch tabs")
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
        withAnimation(BoringMotion.animation(.smooth)) {
            coordinator.currentView = views[0]
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
