import SwiftUI

enum Span: String, CaseIterable, Identifiable {
    case d7 = "7 days", d30 = "30 days", d90 = "90 days", all = "All time"
    var id: Self { self }
    var days: Int? { switch self { case .d7: 7; case .d30: 30; case .d90: 90; case .all: nil } }
}

struct DayPoint: Identifiable {
    let date: Date
    var i: UInt64 = 0, o: UInt64 = 0, li: UInt64 = 0, lo: UInt64 = 0
    var id: Date { date }
    var total: UInt64 { i + o }
}

struct UsageItem: Identifiable {
    let id: String
    var type = ""
    var i: UInt64 = 0, o: UInt64 = 0, li: UInt64 = 0, lo: UInt64 = 0
    var days = 0
    var name: String { id }
    var total: UInt64 { i + o }
    var local: UInt64 { li + lo }
    var avg: UInt64 { total / UInt64(max(days, 1)) }
}

func netType(_ n: String) -> String { n.hasPrefix("Wired") ? "Wired" : "Wi-Fi" }

extension Store {
    /// "Wi-Fi", "Phone hotspot", "Home", "Cellular" or "Wired": from the icon chosen for the network.
    func networkKind(_ n: String) -> String { NetworkEditor.icons.first { $0.symbol == symbol(n) }?.name ?? netType(n) }

    static func date(_ key: String) -> Date { dayFmt.date(from: key) ?? Date() }

    func startKey(_ span: Span) -> String {
        if let n = span.days { return Self.dayFmt.string(from: Calendar.current.date(byAdding: .day, value: -(n - 1), to: Date())!) }
        return (Array(nets.keys) + Array(apps.keys)).min() ?? today
    }

    /// One point per calendar day from the span's start to today, zero-filled. `name` narrows to one app/network.
    func series(_ data: Days, _ span: Span, name: String? = nil) -> [DayPoint] {
        let cal = Calendar.current
        var d = cal.startOfDay(for: Self.date(startKey(span)))
        let end = cal.startOfDay(for: Date())
        var out: [DayPoint] = []
        while d <= end {
            var p = DayPoint(date: d)
            for (n, b) in data[Self.dayFmt.string(from: d)] ?? [:] where name == nil || n == name { p.i += b.i; p.o += b.o; p.li += b.li; p.lo += b.lo }
            out.append(p); d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }

    /// Per-name totals for a range (`from` key onward) or for a single `day`.
    func items(_ data: Days, isNet: Bool, from start: String = "", day: String? = nil) -> [UsageItem] {
        var r: [String: UsageItem] = [:]
        for (k, m) in data where day.map({ $0 == k }) ?? (k >= start) {
            for (n, b) in m {
                var u = r[n] ?? UsageItem(id: n, type: isNet ? networkKind(n) : (paths[n] != nil ? "App" : "Process"))
                u.i += b.i; u.o += b.o; u.li += b.li; u.lo += b.lo; u.days += 1; r[n] = u
            }
        }
        return Array(r.values)
    }
}
