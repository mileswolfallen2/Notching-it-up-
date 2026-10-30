//
//  TopBarSlotConfigurationView.swift
//  boringNotch
//
//  Created by miles allen on 2025-10-30.
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
    @Default(.showShelfTab) private var showShelfTab
    @Default(.showTimerTab) private var showTimerTab

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Order section ───────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tab Order")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Drag to reorder")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Live preview row – one chip per tab in stored order
                HStack(spacing: 8) {
                    ForEach(Array(topBarSlots.enumerated()), id: \.element) { idx, tab in
                        tabChip(for: tab)
                            .onDrag {
                                NSItemProvider(object: NSString(string: "slot:\(idx)"))
                            }
                            .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                                handleDrop(providers, toIndex: idx)
                            }
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            Divider()

            // ── Visibility section ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Tab Visibility")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $showHomeTab) {
                    Label("Home", systemImage: "house.fill")
                }
                .tint(.effectiveAccent)

                Toggle(isOn: $showShelfTab) {
                    Label("Shelf", systemImage: "tray.fill")
                }
                .tint(.effectiveAccent)

                Toggle(isOn: $showTimerTab) {
                    Label("Timer", systemImage: "timer")
                }
                .tint(.effectiveAccent)
            }

            // ── Reset ───────────────────────────────────────────────────
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    withAnimation { topBarSlots = TopBarTab.defaultLayout }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Chip view

    @ViewBuilder
    private func tabChip(for tab: TopBarTab) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                Image(systemName: tab.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.primary)
            }
            .cornerRadius(8)
            .contentShape(RoundedRectangle(cornerRadius: 8))

            Text(tab.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider], toIndex: Int) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                let raw: String
                if let ns = item as? NSString { raw = ns as String }
                else if let s = item as? String { raw = s }
                else { return }

                guard raw.hasPrefix("slot:"),
                      let from = Int(raw.replacingOccurrences(of: "slot:", with: "")),
                      from != toIndex,
                      from >= 0 && from < self.topBarSlots.count,
                      toIndex >= 0 && toIndex < self.topBarSlots.count
                else { return }

                DispatchQueue.main.async {
                    var slots = self.topBarSlots
                    let moved = slots.remove(at: from)
                    let dest  = toIndex > from ? toIndex - 1 : toIndex
                    slots.insert(moved, at: dest)
                    self.topBarSlots = slots
                }
            }
            return true
        }
        return false
    }
}
