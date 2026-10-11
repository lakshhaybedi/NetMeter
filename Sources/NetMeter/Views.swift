import SwiftUI
import Charts
import ServiceManagement

let downColor = Color.cyan, upColor = Color.orange

struct SectionTitle: View {
    let text: String, symbol: String
    init(_ t: String, _ s: String) { text = t; symbol = s }
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
    }
}

/// One usage line: icon, title, value, a proportion bar, and a small detail line.
struct Row: View {
    var nsIcon: NSImage? = nil
    var symbol = "app"
    let title: String, value: String
    var detail = ""
    let fraction: Double
    var tint: Color = .accentColor
    var size = Size.m
    var pinned: Bool? = nil          // nil = no pin button
    var onPin: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil  // right-click → Hide
    var onEdit: (() -> Void)? = nil  // right-click → limit / billing cycle / used so far (networks)
    @AppStorage("showIcons") private var showIcons = true
    @AppStorage("showBars") private var showBars = true
    @AppStorage("showDetail") private var showDetail = true
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            if !showIcons {
                EmptyView()
            } else if let nsIcon {
                Image(nsImage: nsIcon).resizable().frame(width: size.icon, height: size.icon)
            } else {
                Image(systemName: symbol).font(.system(size: size.icon * 0.54)).foregroundStyle(tint)
                    .frame(width: size.icon, height: size.icon).background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size.icon * 0.27))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).lineLimit(1)
                    if let pinned, let onPin, hover || pinned {
                        Button(action: onPin) {
                            Image(systemName: pinned ? "star.fill" : "star").font(.caption)
                                .foregroundStyle(pinned ? Color.yellow : Color.secondary)
                        }.buttonStyle(.plain).help(pinned ? "Unpin" : "Pin to top").accessibilityLabel(pinned ? "Unpin \(title)" : "Pin \(title)")
                    }
                    Spacer()
                    Text(value).monospacedDigit().fontWeight(.medium)
                }
                if size != .s && showBars {
                    Capsule().fill(.quaternary).frame(height: size == .l ? 6 : 4).overlay(alignment: .leading) {
                        GeometryReader { g in
                            Capsule().fill(tint.gradient).frame(width: max(4, g.size.width * min(max(fraction, 0), 1)))
                        }
                    }.accessibilityHidden(true)
                }
                if size != .s && showDetail && !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8) }
            }
        }
        .contentShape(Rectangle()).onHover { hover = $0 }
        .contextMenu {
            if let onEdit {
                Button("Set Limit and Reset Day…", systemImage: "gauge.with.dots.needle.33percent", action: onEdit)
                Button("Set Used So Far…", systemImage: "arrow.triangle.2.circlepath", action: onEdit)
                Divider()
            }
            if let onHide { Button("Hide “\(title)”", systemImage: "eye.slash", action: onHide) }
        }
    }
}

struct Panel: View {
    @ObservedObject var s: Store
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) var openSettings
    @AppStorage("period") var period = Period.month
    @AppStorage("showSubtitle") var showSubtitle = true
    @AppStorage("showFooter") var showFooter = true
    @AppStorage("collapseOtherNets") var collapseOthers = true
    @AppStorage("showOtherNets") var showOthers = false
    @AppStorage("onboarded") var onboarded = false

    var body: some View {
        Group {
            if let n = s.editingNetwork { NetworkEditor(s: s, network: n, done: { s.editingNetwork = nil }) }
            else { overview }
        }
        // Fixed size: SwiftUI doesn't reliably shrink/re-anchor a MenuBarExtra window when content height
        // changes, which left the panel hanging below the menu bar. Content scrolls inside instead.
        .padding(14).frame(width: 360, height: Self.height)
    }

    static var height: CGFloat { min(620, (NSScreen.main?.visibleFrame.height ?? 800) - 120) }

    var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            top
            if onboarded && !s.locationAllowed {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash").foregroundStyle(.orange)
                    Text("Network names need Location access.").font(.caption)
                    Spacer()
                    Button("Allow…") { s.requestLocation() }.controlSize(.small)
                }.padding(8).background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                Picker("", selection: $period) { ForEach(Period.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden()
                Menu {
                    Picker("Traffic", selection: $s.scope) { ForEach(Scope.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                } label: { Image(systemName: s.scope.symbol) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Showing: \(s.scope.rawValue)")
                    .accessibilityLabel("Traffic shown").accessibilityValue(s.scope.rawValue)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let shown = s.layout.filter { !$0.hidden }
                    ForEach(shown) { cfg in section(cfg) }
                    if shown.isEmpty { Text("All sections are hidden. Turn them back on in Settings → Layout.").font(.callout).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity).scrollIndicators(.hidden)
            if showFooter { footer }
        }
    }

    @ViewBuilder func section(_ cfg: SectionCfg) -> some View {
        SectionBox(s: s, id: cfg.id) {
            switch cfg.id {
            case .speed: speedCard(cfg.size)
            case .networks: networks(cfg)
            case .pinned: pinnedSection(cfg)
            case .apps: appsSection(cfg)
            }
        }
    }

    var top: some View {
        HStack(spacing: 10) {
            Image(systemName: s.network.hasPrefix("Wired") || s.network == "Offline/Wired" ? "cable.connector" : "wifi")
                .foregroundStyle(.white).frame(width: 34, height: 34)
                .background(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.network).font(.headline)
                if showSubtitle || s.paused { Text(s.paused ? "Tracking paused" : s.network == "Offline/Wired" ? "Offline" : s.monthUsed(s.network))
                    .font(.caption).foregroundStyle(.secondary).help("Internet download this month, counted against your ISP limit") }
            }
            Spacer()
            Button { s.paused.toggle() } label: { Image(systemName: s.paused ? "play.fill" : "pause.fill").frame(width: 26, height: 26).contentShape(Rectangle()) }
                .help(s.paused ? "Resume tracking" : "Pause tracking").accessibilityLabel(s.paused ? "Resume tracking" : "Pause tracking")
            Button { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } label: { Image(systemName: "macwindow").frame(width: 26, height: 26).contentShape(Rectangle()) }
                .help("Open main window (⌘0)").accessibilityLabel("Open main window")
            Button { openSettings(); NSApp.activate(ignoringOtherApps: true) } label: { Image(systemName: "gearshape").frame(width: 26, height: 26).contentShape(Rectangle()) }.help("Settings (⌘,)").accessibilityLabel("Settings")
        }
        .buttonStyle(.borderless).font(.body)
    }

    func speedCard(_ size: Size) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label(speed(s.down), systemImage: "arrow.down").foregroundStyle(downColor)
                Label(speed(s.up), systemImage: "arrow.up").foregroundStyle(upColor)
            }
            .font(.system(size == .s ? .caption : .callout, design: .rounded).weight(.semibold)).monospacedDigit()
            .frame(width: size == .s ? 96 : 112, alignment: .leading)
            Chart {
                ForEach(Array(s.downHist.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("t", i), y: .value("v", v), series: .value("s", "dA"))
                        .foregroundStyle(downColor.opacity(0.3)).interpolationMethod(.monotone)
                    LineMark(x: .value("t", i), y: .value("v", v), series: .value("s", "dL"))
                        .foregroundStyle(downColor).interpolationMethod(.monotone)
                }
                ForEach(Array(s.upHist.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("t", i), y: .value("v", v), series: .value("s", "u"))
                        .foregroundStyle(upColor).interpolationMethod(.monotone)
                }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: size.chart)
            .accessibilityLabel("Live traffic graph").accessibilityValue("Download \(speed(s.down)), upload \(speed(s.up))")
        }
        .padding(size == .s ? 6 : 10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder func networks(_ cfg: SectionCfg) -> some View {
        let rows = s.netSums(s.visNets, period)
        let mx = Double(max(rows.map { $0.b.i }.max() ?? 1, 1))
        let focus = collapseOthers && s.network != "Offline/Wired"   // show only what's connected; the rest go under a dropdown
        let current = rows.first { $0.name == s.network } ?? (name: s.network, b: Bytes())
        let shown = focus ? [current] : Array(rows.prefix(cfg.limit))
        let others = focus ? rows.filter { $0.name != s.network } : []
        VStack(alignment: .leading, spacing: cfg.size.gap) {
            if rows.isEmpty && !focus {
                Text("Collecting data… usage appears within a few seconds.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(shown, id: \.name) { n in networkRow(n, cfg, mx) }
            if !others.isEmpty {
                DisclosureGroup(isExpanded: $showOthers) {
                    VStack(alignment: .leading, spacing: cfg.size.gap) {
                        ForEach(Array(others.prefix(cfg.limit)), id: \.name) { n in networkRow(n, cfg, mx) }
                    }.padding(.top, 6)
                } label: { Text("Other networks · \(others.count)").font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    func networkRow(_ n: (name: String, b: Bytes), _ cfg: SectionCfg, _ mx: Double) -> some View {
        // With a limit set, the bar shows progress through the billing cycle whichever period is selected
        let limit = s.budgets[n.name]
        let used = Double(s.monthDownload(n.name))
        let frac = limit.map { used / ($0 * 1e9) } ?? Double(n.b.i) / mx
        let tint: Color = limit == nil ? .accentColor : frac >= 1 ? .red : frac >= 0.8 ? .orange : .accentColor
        return Row(symbol: s.symbol(n.name), title: n.name, value: fmt(n.b.i),
            detail: s.detail(n.b) + (limit.map { " · \(Int((frac * 100).rounded()))% of \($0.formatted()) GB" } ?? ""),
            fraction: frac, tint: tint, size: cfg.size,
            onHide: { s.hide(n.name, net: true) }, onEdit: { s.editingNetwork = n.name })
            .help(limit.map { "\(fmt(UInt64(used))) of \($0.formatted()) GB this cycle · resets \(s.cycleReset(n.name).formatted(.dateTime.day().month(.abbreviated)))" } ?? "")
    }

    @ViewBuilder func pinnedSection(_ cfg: SectionCfg) -> some View {
        let pin = Array(s.pinnedUsage(period).prefix(cfg.limit))
        VStack(alignment: .leading, spacing: cfg.size.gap) {
            if pin.isEmpty {
                Text("Hover an app below and click ☆, or add apps in Settings → Apps.").font(.callout).foregroundStyle(.secondary)
            } else {
                let mx = Double(max(pin.map { $0.b.total }.max() ?? 1, 1))
                ForEach(pin, id: \.app.id) { p in
                    Row(nsIcon: s.pinIcon(p.app), title: p.app.name, value: fmt(p.b.total),
                        detail: s.detail(p.b), fraction: Double(p.b.total) / mx, tint: .indigo, size: cfg.size)
                }
            }
        }
    }

    @ViewBuilder func appsSection(_ cfg: SectionCfg) -> some View {
        let all = s.sums(s.visApps, period)
        VStack(alignment: .leading, spacing: cfg.size.gap) {
            if all.isEmpty {
                Text("No app traffic yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                let mx = Double(max(all.first?.b.total ?? 1, 1))
                ForEach(Array(all.prefix(cfg.limit)), id: \.name) { a in
                    Row(nsIcon: s.icon(a.name), title: a.name, value: fmt(a.b.total),
                        detail: s.detail(a.b), fraction: Double(a.b.total) / mx, size: cfg.size,
                        pinned: s.isPinned(a.name), onPin: { s.togglePin(a.name) }, onHide: { s.hide(a.name, net: false) })
                }
            }
        }
    }

    var footer: some View {
        HStack {
            let t = s.netSums(s.visNets, period).reduce(Bytes()) { var r = $0; r.add($1.b); return r }
            Text("\(period.rawValue) · ↓ \(fmt(t.i))  ↑ \(fmt(t.o)) · \(s.scope == .all ? "all traffic" : s.scope.rawValue.lowercased())").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q").buttonStyle(.borderless).font(.caption)
        }
    }
}
