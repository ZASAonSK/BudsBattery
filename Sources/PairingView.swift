import SwiftUI

/// First-run screen: shows the Buds sets heard nearby and lets the user pick one.
struct PairingView: View {
    @EnvironmentObject var store: BudsStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(spacing: 24) {
                    Pulse().padding(.top, 40)
                    VStack(spacing: 8) {
                        Text(L("Connect your earbuds")).font(.largeTitle.bold())
                        Text(hint).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if store.denied {
                        Button(L("Open Settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .glassButton()
                    } else if store.bluetoothReady {
                        let nearby = store.candidates.filter { context.date.timeIntervalSince($0.lastSeen) <= 12 }
                        if nearby.isEmpty {
                            ProgressView().padding(.top, 8)
                        } else {
                            VStack(spacing: 14) {
                                ForEach(nearby) { CandidateRow(candidate: $0) }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    private var hint: String {
        if store.denied { return L("Allow Bluetooth for this app in Settings.") }
        if !store.bluetoothReady { return L("Turn on Bluetooth.") }
        return L("Open the case and hold it close to your phone. Your earbuds will appear below.")
    }
}

private struct CandidateRow: View {
    @EnvironmentObject var store: BudsStore
    let candidate: Candidate

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "earbuds").font(.title2).frame(width: 44, height: 44)
                .background(.white.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name).font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "cellularbars", variableValue: min(max(Double(candidate.rssi + 90) / 50, 0), 1))
                .foregroundStyle(.secondary)
            Button(L("Use")) { store.choose(candidate) }.glassButton()
        }
        .padding(16)
        .glassCard(cornerRadius: 26)
    }

    private var summary: String {
        let parts = [(L("L"), candidate.left), (L("R"), candidate.right), (L("Case"), candidate.caseLevel)]
            .compactMap { name, value in value.map { "\(name) \($0) %" } }
        return parts.isEmpty ? L("Battery not reported yet") : parts.joined(separator: " · ")
    }
}

private struct Pulse: View {
    @State private var on = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle().stroke(.white.opacity(0.3), lineWidth: 1.5)
                    .scaleEffect(on ? 1.9 : 0.5).opacity(on ? 0 : 0.9)
                    .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.8), value: on)
            }
            Image(systemName: "earbuds").font(.system(size: 52, weight: .light))
                .frame(width: 110, height: 110)
                .glassCard(cornerRadius: 55)
        }
        .frame(width: 200, height: 200)
        .onAppear { on = true }
    }
}
