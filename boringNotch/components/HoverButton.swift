//
//  HoverButton.swift
//  boringNotch
//
//  Created by Kraigo on 04.09.2024.
//

import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var accessibilityLabel: String? = nil
    var accessibilityHint: String? = nil
    var accessibilityValue: String? = nil
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect;
    
    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)
        
        Button(action: action) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(isHovering ? Color.gray.opacity(0.2) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(systemName: icon)
                                .foregroundColor(iconColor)
                                .contentTransition(contentTransition)
                                .font(scale == .large ? .largeTitle : .body)
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text(accessibilityLabel ?? fallbackLabel))
        .accessibilityHint(Text(accessibilityHint ?? ""))
        .accessibilityValue(Text(accessibilityValue ?? ""))
        .onHover { hovering in
            withAnimation(BoringMotion.animation(.smooth(duration: 0.3))) {
                isHovering = hovering
            }
        }
    }

    private var fallbackLabel: String {
        let cleaned = icon
            .replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
        return cleaned.prefix(1).uppercased() + String(cleaned.dropFirst())
    }
}
