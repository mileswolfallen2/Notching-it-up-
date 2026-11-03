//
//  BoringNotchWindow.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 06/08/24.
//

import Cocoa

/// Tracks whether the notch panel is allowed to become key so the Notes tab can
/// accept keyboard input. Every other tab keeps the original non-key behavior.
enum NotchTextInput {
    static var isEnabled = false

    static func begin() {
        isEnabled = true
    }

    static func end() {
        isEnabled = false
        guard let window = notchWindow, window.isKeyWindow else { return }
        window.makeFirstResponder(nil)
        window.resignKey()
    }

    private static var notchWindow: NSWindow? {
        NSApp.windows.first { $0 is BoringNotchSkyLightWindow || $0 is BoringNotchWindow }
    }
}

class BoringNotchWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
    }
    
    override var canBecomeKey: Bool {
        NotchTextInput.isEnabled
    }
    
    override var canBecomeMain: Bool {
        false
    }
}
