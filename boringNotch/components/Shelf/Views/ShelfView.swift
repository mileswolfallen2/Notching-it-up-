//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit
import Defaults

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @Default(.enableClipboardHistory) var enableClipboardHistory
    private let spacing: CGFloat = 8
    @State private var clipboardItems: [ClipboardItem] = []
    @State private var clipboardTimer: Timer?

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
        .onAppear {
            if enableClipboardHistory {
                startClipboardMonitoring()
            }
        }
        .onDisappear {
            clipboardTimer?.invalidate()
            clipboardTimer = nil
        }
        .onChange(of: enableClipboardHistory) { _, newValue in
            if newValue {
                startClipboardMonitoring()
            } else {
                clipboardTimer?.invalidate()
                clipboardTimer = nil
                clipboardItems = []
            }
        }
    }
    
    private func startClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardItems = []
        let pasteboard = NSPasteboard.general
        var lastChangeCount = pasteboard.changeCount
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
            if pasteboard.changeCount != lastChangeCount {
                lastChangeCount = pasteboard.changeCount
                if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DispatchQueue.main.async { [self] in
                        if self.clipboardItems.first?.content == string {
                            return
                        }
                        let item = ClipboardItem(id: UUID(), content: String(string.prefix(200)), date: Date())
                        self.clipboardItems.insert(item, at: 0)
                        if self.clipboardItems.count > 30 {
                            self.clipboardItems.removeLast()
                        }
                    }
                } else if let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
                    DispatchQueue.main.async { [self] in
                        let item = ClipboardItem(content: "[Image]", image: image)
                        if self.clipboardItems.first?.content == "[Image]" {
                            return
                        }
                        self.clipboardItems.insert(item, at: 0)
                        if self.clipboardItems.count > 30 {
                            self.clipboardItems.removeLast()
                        }
                    }
                }
            }
        }
        RunLoop.current.add(clipboardTimer!, forMode: .common)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
    }

    var content: some View {
        Group {
            if tvm.isEmpty && clipboardItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        if enableClipboardHistory {
                            ForEach(clipboardItems) { clip in
                                ClipboardItemView(item: clip)
                            }
                        }
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    var content: String
    var image: NSImage?
    let date: Date
    
    init(id: UUID = UUID(), content: String, image: NSImage? = nil, date: Date = Date()) {
        self.id = id
        self.content = content
        self.image = image
        self.date = date
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct ClipboardItemView: View {
    let item: ClipboardItem
    @State private var isHovering = false
    
    var body: some View {
        VStack {
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.gray.opacity(0.3))
                    Image(systemName: "doc.text")
                        .foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)
            }
            Text(item.content)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 70)
                .foregroundStyle(.white)
        }
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let image = item.image {
                pasteboard.writeObjects([image])
            } else {
                pasteboard.setString(item.content, forType: .string)
            }
        }
        .help("Click to copy to clipboard")
    }
}
