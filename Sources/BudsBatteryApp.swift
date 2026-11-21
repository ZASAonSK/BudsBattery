import SwiftUI

@main
struct BudsBatteryApp: App {
    @StateObject private var store = BudsStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { store.setActive($0 == .active) }
        }
    }
}

private struct RootView: View {
    @EnvironmentObject var store: BudsStore

    var body: some View {
        ZStack {
            AuroraBackground()
            if store.isSetUp {
                ContentView()
            } else {
                PairingView()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: store.isSetUp)
    }
}
