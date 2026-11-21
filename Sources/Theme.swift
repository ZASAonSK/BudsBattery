import SwiftUI

/// Liquid Glass on iOS 26+, frosted material before. The glass code is behind
/// `compiler(>=6.2)` so the project still builds with an older Xcode.
extension View {
    @ViewBuilder func glassCard(cornerRadius: CGFloat = 30) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            materialCard(cornerRadius)
        }
        #else
        materialCard(cornerRadius)
        #endif
    }

    @ViewBuilder func glassButton() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        buttonStyle(.borderedProminent)
        #endif
    }

    fileprivate func materialCard(_ cornerRadius: CGFloat) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.14)))
    }
}

func batteryColors(_ value: Int) -> [Color] {
    switch value {
    case 41...: return [Color(red: 0.45, green: 0.98, blue: 0.62), Color(red: 0.1, green: 0.8, blue: 0.55)]
    case 21...: return [.yellow, .orange]
    default: return [.orange, .red]
    }
}

/// Slowly drifting colour blobs behind the glass.
struct AuroraBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.09)
            Circle().fill(Color.blue.opacity(0.55)).frame(width: 340).blur(radius: 90)
                .offset(x: drift ? -100 : 90, y: -250)
            Circle().fill(Color.purple.opacity(0.5)).frame(width: 300).blur(radius: 90)
                .offset(x: drift ? 120 : -80, y: drift ? 40 : 160)
            Circle().fill(Color.teal.opacity(0.4)).frame(width: 280).blur(radius: 90)
                .offset(x: drift ? -70 : 110, y: 330)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
