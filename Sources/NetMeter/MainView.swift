import SwiftUI
import Charts

enum MainTab: String, CaseIterable, Identifiable {
    case overview = "Overview", history = "History", apps = "Apps", networks = "Networks"
    var id: Self { self }
    var symbol: String {
        switch self { case .overview: "chart.bar.xaxis"; case .history: "calendar"; case .apps: "square.grid.2x2"; case .networks: "network" }
    }
}

struct MainView: View {
    @ObservedObject var s: Store
    @AppStorage("mainTab") var tab = MainTab.overview
    @AppStorage("span") var span = Span.d30
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        NavigationSplitView {
            List(MainTab.allCases, selection: Binding<MainTab?>(get: { tab }, set: { tab = $0 ?? tab })) { t in
                Label(t.rawValue, systemImage: t.symbol).tag(t)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } detail: {
            Group {
                switch tab {
                case .overview: OverviewTab(s: s, span: span)
                case .history: HistoryTab(s: s, span: span)
                case .apps: BrowseTab(s: s, span: span, isNet: false)
                case .networks: BrowseTab(s: s, span: span, isNet: true)
                }
            }
            .navigationTitle(tab.rawValue)
            .toolbar {
                ToolbarItem {
                    Picker("Traffic", selection: $s.scope) { ForEach(Scope.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                        .pickerStyle(.segmented).help("Internet = what your ISP meters; Local = this Mac and your home network")
                }
                ToolbarItem {
                    Picker("Range", selection: $span) { ForEach(Span.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                }
            }
        }
        .sheet(isPresented: Binding(get: { s.mainEditing != nil }, set: { if !$0 { s.mainEditing = nil } })) {
            if let n = s.mainEditing { NetworkEditor(s: s, network: n, done: { s.mainEditing = nil }).padding().frame(width: 460, height: 560) }
        }
        .frame(minWidth: 900, minHeight: 600)
        // menu-bar-only app: show in the Dock only while one of its windows is open
        .onAppear { WindowPolicy.opened() }
        .onDisappear { WindowPolicy.closed() }
        .sheet(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            WelcomeView(s: s) { onboarded = true; s.requestLocation(); s.requestNotifications() }.interactiveDismissDisabled()
        }
    }
}

struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StatCard: View {
    let label: String, value: String, symbol: String, color: Color
    var sub = ""
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                if !sub.isEmpty { Text(sub).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(minHeight: 84).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct DailyChart: View {
    let points: [DayPoint]
    var scope = Scope.all
    var height: CGFloat = 240
    @State private var sel: Date?

    var picked: DayPoint? { sel.flatMap { s in points.first { Calendar.current.isDate($0.date, inSameDayAs: s) } } }

    var body: some View {
        Chart {
            ForEach(points) { p in
                // "All traffic" splits out the local part so internet vs local is visible at a glance
                let down = scope == .all ? (p.i > p.li ? p.i - p.li : 0) : p.i, up = scope == .all ? (p.o > p.lo ? p.o - p.lo : 0) : p.o
                BarMark(x: .value("Day", p.date, unit: .day), y: .value("Bytes", Double(down))).foregroundStyle(by: .value("Direction", "Download"))
                BarMark(x: .value("Day", p.date, unit: .day), y: .value("Bytes", Double(up))).foregroundStyle(by: .value("Direction", "Upload"))
                if scope == .all { BarMark(x: .value("Day", p.date, unit: .day), y: .value("Bytes", Double(p.li + p.lo))).foregroundStyle(by: .value("Direction", "Local")) }
            }
            if let p = picked {
                RuleMark(x: .value("Day", p.date, unit: .day)).foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.date, format: .dateTime.weekday().month().day()).font(.caption.bold())
                            Text("↓ \(fmt(p.i))   ↑ \(fmt(p.o))" + (scope == .all && p.li + p.lo > 0 ? "   ·   \(fmt(p.li + p.lo)) local" : "")).font(.caption2)
                            Text(fmt(p.total)).font(.caption.weight(.semibold))
                        }.padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        .chartForegroundStyleScale(["Download": downColor, "Upload": upColor, "Local": Color.purple])
        .chartXSelection(value: $sel)
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel { if let b = v.as(Double.self) { Text(fmt(UInt64(b))) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: height)
        .accessibilityLabel("Daily traffic chart").accessibilityValue("\(points.count) days, \(fmt(points.reduce(0) { $0 + $1.total })) in total")
    }
}

struct ShareBar: View {
    let value: UInt64, total: UInt64
    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: Double(value), total: Double(max(total, 1))).progressViewStyle(.linear)
            Text("\(Int((Double(value) / Double(max(total, 1)) * 100).rounded()))%").font(.caption).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
        }
    }
}

struct OverviewTab: View {
    @ObservedObject var s: Store
    let span: Span

    var body: some View {
        let start = s.startKey(span)
        let pts = s.series(s.visNets, span)
        let down = pts.reduce(0) { $0 + $1.i }, up = pts.reduce(0) { $0 + $1.o }
        let active = pts.filter { $0.total > 0 }
        let busiest = active.max { $0.total < $1.total }
        let localTotal = s.items(s.visApps, isNet: false, from: start).reduce(0) { $0 + $1.local }
        let apps = s.items(s.visApps, isNet: false, from: start).sorted { $0.total > $1.total }
        let nets = s.items(s.visNets, isNet: true, from: start).sorted { $0.total > $1.total }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    StatCard(label: "Download", value: fmt(down), symbol: "arrow.down", color: downColor, sub: s.scope.rawValue)
                    StatCard(label: "Upload", value: fmt(up), symbol: "arrow.up", color: upColor, sub: s.scope.rawValue)
                    StatCard(label: "Local traffic", value: fmt(localTotal), symbol: "house", color: .purple, sub: "stayed on this Mac / home network")
                    StatCard(label: "Used this month", value: fmt(s.monthDownload(s.network)), symbol: "calendar", color: .pink, sub: "\(s.network) · internet download")
                    StatCard(label: "Daily average", value: fmt((down + up) / UInt64(max(active.count, 1))), symbol: "chart.bar", color: .green,
                             sub: "over \(active.count) active days")
                    StatCard(label: "Busiest day", value: busiest.map { fmt($0.total) } ?? "—", symbol: "flame", color: .orange,
                             sub: busiest.map { $0.date.formatted(.dateTime.weekday().month().day()) } ?? "")
                }
                Card(title: "Daily traffic") { DailyChart(points: pts, scope: s.scope, height: 260) }
                HStack(alignment: .top, spacing: 14) {
                    Card(title: "Top apps") {
                        let mx = Double(max(apps.first?.total ?? 1, 1))
                        ForEach(apps.prefix(8)) { a in
                            Row(nsIcon: s.icon(a.name), title: a.name, value: fmt(a.total), detail: s.detail(Bytes(i: a.i, o: a.o, li: a.li, lo: a.lo)), fraction: Double(a.total) / mx,
                                onHide: { s.hide(a.name, net: false) })
                        }
                        if apps.isEmpty { Text("No data in this range.").foregroundStyle(.secondary) }
                    }
                    Card(title: "Networks") {
                        let mx = Double(max(nets.map { $0.i }.max() ?? 1, 1))
                        ForEach(nets.prefix(8)) { n in
                            Row(symbol: s.symbol(n.name), title: n.name, value: fmt(n.i),
                                detail: "\(n.type) · " + s.detail(Bytes(i: n.i, o: n.o, li: n.li, lo: n.lo)), fraction: Double(n.i) / mx,
                                onHide: { s.hide(n.name, net: true) }, onEdit: { s.mainEditing = n.name })
                        }
                        if nets.isEmpty { Text("No data in this range.").foregroundStyle(.secondary) }
                    }
                }
            }.padding(20)
        }
    }
}

/// Every day in the range as a sortable table; pick a day to see that day's apps and networks.
struct HistoryTab: View {
    @ObservedObject var s: Store
    let span: Span
    @State private var order = [KeyPathComparator(\DayRow.date, order: .reverse)]
    @State private var appOrder = [KeyPathComparator(\UsageItem.total, order: .reverse)]
    @State private var netOrder = [KeyPathComparator(\UsageItem.total, order: .reverse)]
    @State private var sel: String?

    struct DayRow: Identifiable {
        let id: String
        let date: Date
        let i: UInt64, o: UInt64
        let topApp: String, networks: String
        var total: UInt64 { i + o }
    }

    var rows: [DayRow] {
        let start = s.startKey(span)
        return s.visNets.filter { $0.key >= start }.map { k, m in
            let top = s.visApps[k]?.max { $0.value.total < $1.value.total }?.key ?? "—"
            let names = m.sorted { $0.value.total > $1.value.total }.map(\.key).joined(separator: ", ")
            return DayRow(id: k, date: Store.date(k), i: m.values.reduce(0) { $0 + $1.i }, o: m.values.reduce(0) { $0 + $1.o }, topApp: top, networks: names)
        }
    }

    var body: some View {
        let all = rows
        let key = sel.flatMap { k in all.contains { $0.id == k } ? k : nil } ?? all.max { $0.date < $1.date }?.id
        VSplitView {
            Table(all.sorted(using: order), selection: $sel, sortOrder: $order) {
                TableColumn("Day", value: \.date) { Text($0.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year()) }.width(min: 130, ideal: 160)
                TableColumn("Download", value: \.i) { Text(fmt($0.i)).monospacedDigit() }.width(min: 80, ideal: 90)
                TableColumn("Upload", value: \.o) { Text(fmt($0.o)).monospacedDigit() }.width(min: 80, ideal: 90)
                TableColumn("Total", value: \.total) { Text(fmt($0.total)).monospacedDigit().fontWeight(.medium) }.width(min: 80, ideal: 90)
                TableColumn("Top app", value: \.topApp)
                TableColumn("Networks", value: \.networks)
            }
            .frame(minHeight: 200)
            if let key {
                detail(key)
            } else {
                Text("No usage recorded in this range yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    func detail(_ key: String) -> some View {
        let apps = s.items(s.visApps, isNet: false, day: key).sorted(using: appOrder)
        let nets = s.items(s.visNets, isNet: true, day: key).sorted(using: netOrder)
                return VStack(alignment: .leading, spacing: 8) {
            Text(Store.date(key), format: .dateTime.weekday(.wide).month(.wide).day().year()).font(.headline)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading) {
                    Label("Apps · \(apps.count)", systemImage: "square.grid.2x2").font(.subheadline.weight(.semibold))
                    Table(apps, sortOrder: $appOrder) {
                        TableColumn("App", value: \.name) { u in
                            HStack { Image(nsImage: s.icon(u.name)).resizable().frame(width: 18, height: 18); Text(u.name).lineLimit(1) }
                        }.width(min: 100, ideal: 140)
                        TableColumn("↓", value: \.i) { Text(fmt($0.i)).monospacedDigit() }.width(min: 52, ideal: 62)
                        TableColumn("↑", value: \.o) { Text(fmt($0.o)).monospacedDigit() }.width(min: 52, ideal: 62)
                        TableColumn("Total", value: \.total) { Text(fmt($0.total)).monospacedDigit().fontWeight(.medium) }.width(min: 52, ideal: 62)
                        TableColumn("Local", value: \.local) { Text(fmt($0.local)).monospacedDigit().foregroundStyle(.purple) }.width(min: 52, ideal: 62)
                    }
                }
                VStack(alignment: .leading) {
                    Label("Networks · \(nets.count)", systemImage: "network").font(.subheadline.weight(.semibold))
                    Table(nets, sortOrder: $netOrder) {
                        TableColumn("Network", value: \.name) { u in
                            Label(u.name, systemImage: s.symbol(u.name)).lineLimit(1)
                        }.width(min: 100, ideal: 130)
                        TableColumn("Type", value: \.type) { Text($0.type) }.width(min: 45, ideal: 52)
                        TableColumn("↓", value: \.i) { Text(fmt($0.i)).monospacedDigit() }.width(min: 52, ideal: 62)
                        TableColumn("↑", value: \.o) { Text(fmt($0.o)).monospacedDigit() }.width(min: 52, ideal: 62)
                        TableColumn("Total", value: \.total) { Text(fmt($0.total)).monospacedDigit().fontWeight(.medium) }.width(min: 52, ideal: 62)
                    }
                }
            }
        }
        .padding(12).frame(minHeight: 240)
    }
}

/// All apps or all networks over the range; pick one to see its daily history.
struct BrowseTab: View {
    @ObservedObject var s: Store
    let span: Span
    let isNet: Bool
    @State private var order = [KeyPathComparator(\UsageItem.total, order: .reverse)]
    @State private var sel: String?

    var body: some View {
        let data = isNet ? s.visNets : s.visApps
        let all = s.items(data, isNet: isNet, from: s.startKey(span))
        let total = all.reduce(0) { $0 + $1.total }
        let key = sel.flatMap { k in all.contains { $0.id == k } ? k : nil } ?? all.max { $0.total < $1.total }?.id
        VSplitView {
            Table(all.sorted(using: order), selection: $sel, sortOrder: $order) {
                TableColumn(isNet ? "Network" : "App", value: \.name) { u in
                    if isNet { Label(u.name, systemImage: s.symbol(u.name)).lineLimit(1) }
                    else { HStack { Image(nsImage: s.icon(u.name)).resizable().frame(width: 18, height: 18); Text(u.name).lineLimit(1) } }
                }.width(min: 130, ideal: 150)
                TableColumn("Type", value: \.type) { Text($0.type) }.width(min: 60, ideal: 100)
                TableColumn("Download", value: \.i) { Text(fmt($0.i)).monospacedDigit() }.width(min: 70, ideal: 82)
                TableColumn("Upload", value: \.o) { Text(fmt($0.o)).monospacedDigit() }.width(min: 70, ideal: 82)
                TableColumn("Total", value: \.total) { Text(fmt($0.total)).monospacedDigit().fontWeight(.medium) }.width(min: 70, ideal: 82)
                TableColumn("Local", value: \.local) { Text(fmt($0.local)).monospacedDigit().foregroundStyle(.purple) }.width(min: 60, ideal: 74)
                TableColumn("Avg / day", value: \.avg) { Text(fmt($0.avg)).monospacedDigit() }.width(min: 70, ideal: 84)
                TableColumn("Days", value: \.days) { Text("\($0.days)").monospacedDigit() }.width(min: 36, ideal: 44)
                TableColumn("Share") { ShareBar(value: $0.total, total: total) }.width(min: 70, ideal: 90)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if isNet, ids.count == 1, let n = ids.first {
                    Button("Set Limit and Reset Day…", systemImage: "gauge.with.dots.needle.33percent") { s.mainEditing = n }
                    Button("Set Used So Far…", systemImage: "arrow.triangle.2.circlepath") { s.mainEditing = n }
                    Divider()
                }
                if !ids.isEmpty { Button("Hide \(ids.count == 1 ? "“\(ids.first!)”" : "\(ids.count) items")") { ids.forEach { s.hide($0, net: isNet) } } }
            }
            .frame(minHeight: 220)
            if let key {
                Card(title: "\(key) · daily usage") { DailyChart(points: s.series(data, span, name: key), scope: s.scope, height: 200) }
                    .padding(12).frame(minHeight: 280)
            } else {
                Text("No data in this range yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
