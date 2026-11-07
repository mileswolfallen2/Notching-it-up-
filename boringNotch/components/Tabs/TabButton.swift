//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    var horizontalPadding: CGFloat = 15
    let onClick: () -> Void

    @State private var hovering = false
    
    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, horizontalPadding)
                .background(
                    Capsule()
                        .fill(selected ? Color.clear : Color.white.opacity(hovering ? 0.06 : 0))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(BoringMotion.animation(.easeOut(duration: 0.15)), value: hovering)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
