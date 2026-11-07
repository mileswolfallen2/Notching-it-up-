//
//  TopBarSlotConfigurationView.swift
//  boringNotch
//
//  Drag-and-drop layout editor for the top bar tab strip.
//  Mirrors the pattern used in MusicSlotConfigurationView.
//

import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct TopBarSlotConfigurationView: View {
    @Default(.topBarSlots) private var topBarSlots
    @Default(.showHomeTab) private var showHomeTab
    @Default(.showWeatherTab) private var showWeatherTab
    @Default(.showShelfTab) private var showShelfTab
    @Default(.showTimerTab) private var showTimerTab
    @Default(.showNotesTab) private var showNotesTab
    @Default(.showAITab) private var showAITab
    @Default(.showDevicesTab) private var showDevicesTab
    @Default(.boringShelf) private var shelfEnabled

    @State private var draggedTab: TopBarTab?

    /// Stored order with any newly introduced tabs appended.
    private var orderedTabs: [TopBarTab] {
        var ordered = topBarSlots
        for tab in TopBarTab.allCases where !ordered.contains(tab) {
            ordered.append(tab)
        }
        return ordered
    }

    private var visibleTabs: [TopBarTab] {
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            previewSection
            Divider()
            visibilitySection

            HStack {
                if !shelfEnabled {
                    Label("The shelf is disabled, so its tab stays hidden.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reset to defaults") {
                    withAnimation(.snappy) {
                        topBarSlots = TopBarTab.defaultLayout
                        showHomeTab = true
                        showWeatherTab = true
                        showShelfTab = true
                        showTimerTab = true
                        showNotesTab = true
                        showAITab = true
                        showDevicesTab = false
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear(perform: normalizeSlots)
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top bar preview")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Drag to reorder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Group {
                if visibleTabs.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(.secondary)
                        Text("All tabs are hidden. Turn one on below to show it in the notch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                } else {
                    HStack(spacing: 8) {
                        ForEach(visibleTabs, id: \.self) { tab in
                            tabChip(for: tab)
                                .opacity(draggedTab == tab ? 0.4 : 1)
                                .onDrag {
                                    DispatchQueue.main.async { draggedTab = tab }
                                    return NSItemProvider(object: NSString(string: "tab:\(tab.rawValue)"))
                                }
                                .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                                    let handled = handleDrop(providers, onto: tab)
                                    DispatchQueue.main.async { draggedTab = nil }
                                    return handled
                                }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Visibility & order

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tabs")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            ForEach(orderedTabs, id: \.self) { tab in
                tabRow(for: tab)
            }
        }
    }

    private func tabRow(for tab: TopBarTab) -> some View {
        let visible = isVisible(tab)
        let shelfBlocked = tab == .shelf && !shelfEnabled

        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)

            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(NSColor.controlBackgroundColor))
                Image(systemName: tab.iconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(tab.label)
                        .fontWeight(.medium)

                    if !visible {
                        Text(shelfBlocked ? "Shelf off" : "Hidden")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.14)))
                    }
                }

                Text(subtitle(for: tab))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: visibilityBinding(for: tab))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(shelfBlocked)
                .accessibilityLabel("Show \(tab.label) tab")
                .help(shelfBlocked ? "Enable the shelf to show this tab" : "Show this tab in the top bar")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.controlBackgroundColor).opacity(visible ? 0.55 : 0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .opacity(visible ? 1 : 0.6)
        .onDrag {
            DispatchQueue.main.async { draggedTab = tab }
            return NSItemProvider(object: NSString(string: "tab:\(tab.rawValue)"))
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
            let handled = handleDrop(providers, onto: tab)
            DispatchQueue.main.async { draggedTab = nil }
            return handled
        }
    }

    private func subtitle(for tab: TopBarTab) -> String {
        switch tab {
        case .home:  return "Music, calendar and live activity"
        case .weather: return "Current conditions and a five-day forecast"
        case .shelf: return "Files and clipboard items"
        case .timer: return "Pomodoro sessions"
        case .notes: return "A quick persistent scratchpad"
        case .ai:    return "AI usage limits across your tools"
        case .devices: return "Connected headphones, speakers, and their battery status"
        }
    }

    private func isVisible(_ tab: TopBarTab) -> Bool {
        switch tab {
        case .home:  return showHomeTab
        case .weather: return showWeatherTab
        case .shelf: return showShelfTab && shelfEnabled
        case .timer: return showTimerTab
        case .notes: return showNotesTab
        case .ai:    return showAITab
        case .devices: return showDevicesTab
        }
    }

    private func visibilityBinding(for tab: TopBarTab) -> Binding<Bool> {
        switch tab {
        case .home:  return $showHomeTab
        case .weather: return $showWeatherTab
        case .shelf: return $showShelfTab
        case .timer: return $showTimerTab
        case .notes: return $showNotesTab
        case .ai:    return $showAITab
        case .devices: return $showDevicesTab
        }
    }

    // MARK: - Chip view

    @ViewBuilder
    private func tabChip(for tab: TopBarTab) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                Image(systemName: tab.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary)
            }
            .cornerRadius(8)
            .contentShape(RoundedRectangle(cornerRadius: 8))

            Text(tab.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func normalizeSlots() {
        let normalized = orderedTabs
        guard normalized != topBarSlots else { return }
        topBarSlots = normalized
    }

    private func handleDrop(_ providers: [NSItemProvider], onto target: TopBarTab) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                let raw: String
                if let ns = item as? NSString { raw = ns as String }
                else if let s = item as? String { raw = s }
                else { return }

                guard raw.hasPrefix("tab:"),
                      let dragged = TopBarTab(rawValue: raw.replacingOccurrences(of: "tab:", with: "")),
                      dragged != target
                else { return }

                DispatchQueue.main.async {
                    var slots = self.orderedTabs
                    guard let from = slots.firstIndex(of: dragged) else { return }

                    withAnimation(.snappy) {
                        slots.remove(at: from)
                        // Re-find the target after removal so dragging across
                        // several tabs inserts instead of swapping endpoints.
                        let to = slots.firstIndex(of: target) ?? slots.count
                        slots.insert(dragged, at: to)
                        self.topBarSlots = slots
                    }
                }
            }
            return true
        }
        return false
    }
}
