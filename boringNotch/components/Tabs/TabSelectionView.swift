//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Timer", icon: "timer", view: .timer)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.showHomeTab) private var showHomeTab
    @Default(.showShelfTab) private var showShelfTab
    @Default(.showTimerTab) private var showTimerTab
    @Default(.topBarSlots) private var topBarSlots
    @Namespace var animation
    @State private var dragOffset: CGFloat = 0
    
    private var visibleTabs: [TabModel] {
        // Use topBarSlots order; fall back to static order for any tabs not in slots
        var orderedTabs: [TabModel] = topBarSlots.compactMap { slot in
            switch slot {
            case .home:  return TabModel(label: "Home",  icon: "house.fill", view: .home)
            case .shelf: return TabModel(label: "Shelf", icon: "tray.fill",  view: .shelf)
            case .timer: return TabModel(label: "Timer", icon: "timer",       view: .timer)
            }
        }
        // Append any tabs not covered by topBarSlots (safety net)
        let coveredViews = Set(orderedTabs.map { $0.view })
        for t in tabs where !coveredViews.contains(t.view) {
            orderedTabs.append(t)
        }
        // Apply visibility filters
        return orderedTabs.filter { tab in
            switch tab.view {
            case .home:  return showHomeTab
            case .shelf: return showShelfTab && Defaults[.boringShelf]
            case .timer: return showTimerTab
            }
        }
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
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    if value.translation.width < -50 {
                        switchTab(by: 1)
                    } else if value.translation.width > 50 {
                        switchTab(by: -1)
                    }
                    dragOffset = 0
                }
        )
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
