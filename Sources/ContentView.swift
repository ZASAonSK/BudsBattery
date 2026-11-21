import SwiftUI
import Charts

private let freshSeconds: TimeInterval = 30

/// Locale-aware durations: "12s", "5m", "3h" and "2h 10m" (units follow the phone's language).
private let agoFormatter: DateComponentsFormatter = {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.day, .hour, .minute, .second]
    f.unitsStyle = .abbreviated
    f.maximumUnitCount = 1
    return f
}()

private let remainingFormatter: DateComponentsFormatter = {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.hour, .minute]
    f.unitsStyle = .abbreviated
    f.maximumUnitCount = 2
    return f
}()

private func ago(_ seconds: TimeInterval) -> String { agoFormatter.string(from: max(seconds, 1)) ?? "" }

private func duration(_ seconds: TimeInterval) -> String { remainingFormatter.string(from: max(seconds, 60)) ?? "" }

struct ContentView: View {
    @EnvironmentObject var store: BudsStore
    @State private var showHistory = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(spacing: 18) {
                    header(now: context.date)
                    if store.hasData {
                        HStack(spacing: 18) {
                            BudCard(title: L("Left"), level: store.left, live: isLive(store.left, .left, context.date),
                                    trend: store.history.trend(\.l), remaining: store.history.remaining(\.l), now: context.date)
                            BudCard(title: L("Right"), level: store.right, live: isLive(store.right, .right, context.date),
                                    trend: store.history.trend(\.r), remaining: store.history.remaining(\.r), now: context.date)
                        }
                        CaseCard(level: store.caseLevel, live: isLive(store.caseLevel, .box, context.date),
                                 trend: store.history.trend(\.c), remaining: store.history.remaining(\.c), now: context.date)
                        Button { showHistory = true } label: {
                            Label(L("Battery history"), systemImage: "chart.xyaxis.line")
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)
                        .glassCard(cornerRadius: 24)
                    } else {
                        waiting
                    }
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showHistory) { HistoryView(samples: store.history) }
    }

    private func isLive(_ level: Level?, _ channel: BudsStore.Channel, _ now: Date) -> Bool {
        store.gattChannels.contains(channel) || (level.map { now.timeIntervalSince($0.date) <= freshSeconds } ?? false)
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.deviceName).font(.largeTitle.bold())
                HStack(spacing: 6) {
                    Circle().fill(statusColor(now: now)).frame(width: 8, height: 8)
                    Text(statusText(now: now)).font(.subheadline).foregroundStyle(.secondary)
                    if let rssi = store.rssi, store.hasData {
                        Image(systemName: "cellularbars", variableValue: min(max(Double(rssi + 90) / 50, 0), 1))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Menu {
                Button { showHistory = true } label: { Label(L("Battery history"), systemImage: "chart.xyaxis.line") }
                Button(role: .destructive) { store.forget() } label: { Label(L("Forget earbuds"), systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 44)
                    .glassCard(cornerRadius: 22)
            }
        }
        .padding(.top, 8)
    }

    private func isOnline(now: Date) -> Bool {
        !store.gattChannels.isEmpty || (store.lastBroadcast.map { now.timeIntervalSince($0) <= freshSeconds } ?? false)
    }

    private func statusColor(now: Date) -> Color { isOnline(now: now) ? .green : .gray }

    private func statusText(now: Date) -> String {
        if store.denied { return L("Allow Bluetooth in Settings") }
        if !store.bluetoothReady { return L("Turn on Bluetooth") }
        if !store.gattChannels.isEmpty { return L("Live · connected") }
        if let b = store.lastBroadcast, now.timeIntervalSince(b) <= freshSeconds { return L("Live · broadcast") }
        guard let newest = [store.left, store.right, store.caseLevel].compactMap({ $0?.date }).max() else {
            return L("Searching for earbuds…")
        }
        return L("Last seen %@ ago", ago(now.timeIntervalSince(newest)))
    }

    private var waiting: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(L("Waiting for data from your earbuds")).font(.headline)
            Text(L("Open the case or put them in your ears.")).font(.subheadline).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity).padding(.vertical, 50)
        .glassCard()
    }
}

/// Arrow and estimate under a value.
private struct Detail: View {
    let live: Bool
    let level: Level?
    let trend: Trend?
    let remaining: TimeInterval?
    let now: Date

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                switch trend {
                case .up: Image(systemName: "arrow.up").foregroundStyle(.green); Text(L("rising"))
                case .down: Image(systemName: "arrow.down").foregroundStyle(.orange); Text(L("falling"))
                case nil: EmptyView()
                }
                if live, trend != .up, let remaining { Text("~\(duration(remaining))") }
            }
            .font(.caption).foregroundStyle(.secondary).frame(height: 16)
            if !live, let level {
                Text(L("%@ ago", ago(now.timeIntervalSince(level.date)))).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct Ring: View {
    let value: Int?

    var body: some View {
        let colors = batteryColors(value ?? 0)
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 12)
            Circle().trim(from: 0, to: CGFloat(value ?? 0) / 100)
                .stroke(AngularGradient(colors: colors + [colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: colors[1].opacity(0.5), radius: 8)
                .animation(.easeOut(duration: 0.7), value: value)
            VStack(spacing: 0) {
                Text(value.map(String.init) ?? "—")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.easeOut, value: value)
                Text("%").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 118, height: 118)
    }
}

private struct BudCard: View {
    let title: String
    let level: Level?
    let live: Bool
    let trend: Trend?
    let remaining: TimeInterval?
    let now: Date

    var body: some View {
        VStack(spacing: 14) {
            Ring(value: level?.value)
            Text(title).font(.headline)
            Detail(live: live, level: level, trend: trend, remaining: remaining, now: now)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
        .glassCard()
        .opacity(live || level == nil ? 1 : 0.7)
    }
}

private struct CaseCard: View {
    let level: Level?
    let live: Bool
    let trend: Trend?
    let remaining: TimeInterval?
    let now: Date

    var body: some View {
        let colors = batteryColors(level?.value ?? 0)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L("Case"), systemImage: "battery.100percent").font(.headline)
                Spacer()
                Text(level.map { "\($0.value) %" } ?? "—").font(.title2.bold().monospacedDigit())
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(level?.value ?? 0) / 100)
                        .shadow(color: colors[1].opacity(0.5), radius: 6)
                        .animation(.easeOut(duration: 0.7), value: level?.value)
                }
            }
            .frame(height: 14)
            Detail(live: live, level: level, trend: trend, remaining: remaining, now: now)
                .frame(maxWidth: .infinity)
        }
        .padding(22)
        .glassCard()
        .opacity(live || level == nil ? 1 : 0.7)
    }
}

private struct HistoryView: View {
    let samples: [Sample]

    private struct Point: Identifiable {
        let id = UUID()
        let series: String, date: Date, value: Int
    }

    private var points: [Point] {
        samples.flatMap { s in
            [(L("Left"), s.l), (L("Right"), s.r), (L("Case"), s.c)].compactMap { name, v in
                v.map { Point(series: name, date: s.date, value: $0) }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if samples.count < 2 {
                    Text(L("Not enough data yet. History is recorded whenever the battery level changes."))
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).padding()
                } else {
                    Chart(points) {
                        LineMark(x: .value(L("Time"), $0.date), y: .value("%", $0.value))
                            .foregroundStyle(by: .value(L("Channel"), $0.series))
                            .interpolationMethod(.stepEnd)
                    }
                    .chartYScale(domain: 0...100)
                    .padding()
                }
            }
            .navigationTitle(L("Battery history"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
