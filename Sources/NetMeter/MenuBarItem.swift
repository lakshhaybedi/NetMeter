import SwiftUI

enum BarStyle: String, CaseIterable, Identifiable {
    case icon = "Icon only", text = "Text only", both = "Icon and text"
    var id: Self { self }
}

enum NumberStyle: String, CaseIterable, Identifiable {
    case full = "Full", compact = "Compact", tiny = "Tiny"
    var id: Self { self }
    var example: String { switch self { case .full: "119.78 GB"; case .compact: "120 GB"; case .tiny: "120G" } }
}

enum BarIcons {
    static let all: [(name: String, symbol: String)] = [
        ("Arrows in a circle", "arrow.up.arrow.down.circle.fill"), ("Arrows", "arrow.up.arrow.down"), ("Gauge", "gauge.with.dots.needle.67percent"),
        ("Chart", "chart.bar.fill"), ("Network", "network"), ("Wi-Fi", "wifi"), ("Antenna", "antenna.radiowaves.left.and.right"), ("Speedometer", "speedometer"),
    ]
}

/// Bytes shortened for the menu bar: "119.78 GB" → "120 GB" (compact) → "120G" (tiny).
func fmtBar(_ b: UInt64, _ style: NumberStyle) -> String {
    if style == .full { return fmt(b) }
    let names = style == .tiny ? ["B", "K", "M", "G", "T"] : ["B", "KB", "MB", "GB", "TB"]
    var v = Double(b), i = 0
    while v >= 999.95, i < 4 { v /= 1000; i += 1 }
    var num = v >= 99.95 || i == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    if num.hasSuffix(".0") { num.removeLast(2) }
    return num + (style == .tiny ? "" : " ") + names[i]
}

private func shortName(_ n: String, _ style: NumberStyle) -> String {
    let max = 8
    return style == .full || n.count <= max ? n : String(n.prefix(max - 1)) + "…"
}

extension Store {
    /// The pieces of text the menu bar item shows, in the user's order. Split across two lines when `stacked`.
    func barLines(_ items: String, _ numbers: NumberStyle, stacked: Bool) -> [String] {
        func speedText(_ v: Double) -> String {
            numbers == .full ? speed(v) : fmtBar(UInt64(v), numbers) + (numbers == .tiny ? "" : "/s")
        }
        var parts: [String] = []
        for it in items.split(separator: ",").compactMap({ Item(rawValue: String($0)) }) {
            switch it {
            case .speed:
                if stacked { parts += ["↓\(speedText(down))", "↑\(speedText(up))"] } else { parts.append("↓\(speedText(down)) ↑\(speedText(up))") }
            case .today: parts.append(fmtBar(total(visNets, .day), numbers))
            case .month: parts.append(fmtBar(monthDownload(network), numbers) + (numbers == .full ? "/mo" : ""))
            case .network:
                let m = netSums(visNets, .month).first { $0.name == network }?.b.total ?? 0
                parts.append("\(shortName(network, numbers)) \(fmtBar(m, numbers))")
            case .pinned:
                parts += pinnedUsage(.day).map { "\(shortName($0.app.name, numbers)) \(fmtBar($0.b.total, numbers))" }
            case .topApp:
                if let t = sums(visApps, .day).first { parts.append("\(shortName(t.name, numbers)) \(fmtBar(t.b.total, numbers))") }
            }
        }
        guard stacked, parts.count >= 2 else { return parts.isEmpty ? [] : [parts.joined(separator: " · ")] }
        let half = (parts.count + 1) / 2
        return [parts[..<half].joined(separator: " · "), parts[half...].joined(separator: " · ")]
    }
}

/// Draws the menu bar item for explicit settings (so variants can be previewed side by side).
struct BarView: View {
    @ObservedObject var s: Store
    let items: String, style: BarStyle, icon: String, numbers: NumberStyle, stacked: Bool

    var body: some View {
        let lines = style == .icon ? [] : s.barLines(items, numbers, stacked: stacked)
        HStack(spacing: 4) {
            if style != .text || lines.isEmpty { Image(systemName: s.paused ? "pause.circle" : icon) }   // never leave the item invisible
            if lines.count == 1 {
                Text(lines[0])
            } else if lines.count > 1 {
                VStack(alignment: .trailing, spacing: -1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { Text($0.element) }
                }.font(.system(size: 9.5, weight: .semibold))
            }
        }
        .monospacedDigit()
    }
}

/// The menu bar item, driven by the user's settings; also the live preview in Settings.
struct BarContent: View {
    @ObservedObject var s: Store
    @AppStorage("items") private var items = "Used this month"
    @AppStorage("barStyle") private var style = BarStyle.both
    @AppStorage("barIcon") private var icon = "arrow.up.arrow.down.circle.fill"
    @AppStorage("barNumbers") private var numbers = NumberStyle.compact
    @AppStorage("barStacked") private var stacked = false

    var body: some View { BarView(s: s, items: items, style: style, icon: icon, numbers: numbers, stacked: stacked) }
}
