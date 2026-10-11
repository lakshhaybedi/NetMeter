import SwiftUI
import CoreWLAN
import CoreLocation
import UserNotifications
import UniformTypeIdentifiers

struct Bytes: Codable {
    var i: UInt64 = 0, o: UInt64 = 0      // everything counted
    var li: UInt64 = 0, lo: UInt64 = 0    // the part of i/o that stayed local: this Mac (loopback) or the home network
    var total: UInt64 { i + o }
    var local: UInt64 { li + lo }

    enum CodingKeys: String, CodingKey { case i, o, li, lo }
    init(i: UInt64 = 0, o: UInt64 = 0, li: UInt64 = 0, lo: UInt64 = 0) { self.i = i; self.o = o; self.li = li; self.lo = lo }
    init(from d: Decoder) throws {          // older data.json has no li/lo
        let c = try d.container(keyedBy: CodingKeys.self)
        i = try c.decode(UInt64.self, forKey: .i); o = try c.decode(UInt64.self, forKey: .o)
        li = try c.decodeIfPresent(UInt64.self, forKey: .li) ?? 0; lo = try c.decodeIfPresent(UInt64.self, forKey: .lo) ?? 0
    }

    mutating func add(_ b: Bytes) { i += b.i; o += b.o; li += b.li; lo += b.lo }

    /// i/o rewritten for the chosen view; li/lo are kept so "local" can still be shown next to it.
    func scoped(_ s: Scope) -> Bytes {
        var b = self
        switch s {
        case .all: break
        case .internet: b.i = i > li ? i - li : 0; b.o = o > lo ? o - lo : 0
        case .local: b.i = min(li, i); b.o = min(lo, o)
        }
        return b
    }
}

enum Scope: String, CaseIterable, Identifiable {
    case internet = "Internet", local = "Local", all = "All traffic"
    var id: Self { self }
    var symbol: String { switch self { case .internet: "globe"; case .local: "house"; case .all: "arrow.up.arrow.down" } }
}
typealias Days = [String: [String: Bytes]]   // "yyyy-MM-dd" -> name -> bytes

struct Saved: Codable {
    var nets: Days = [:]; var apps: Days = [:]; var notified: Set<String> = []
    var paths: [String: String]?, budgets: [String: Double]?   // optional so older data.json still decodes
    var hiddenNets: [String]?, hiddenApps: [String]?
    var aliases: [String: String]?
    var baselines: [String: Int64]?
    var cycleDays: [String: Int]?, symbols: [String: String]?
    var pinned: [PinnedApp]?
}

enum Period: String, CaseIterable { case day = "Day", week = "Week", month = "Month" }

enum Item: String, CaseIterable {
    case speed = "Live speed", today = "Today total", month = "Used this month"
    case network = "Current network (month)", topApp = "Top app today", pinned = "Pinned apps today"
}

func speed(_ v: Double) -> String { fmt(UInt64(v)) + "/s" }
func fmt(_ b: UInt64) -> String { b == 0 ? "0 B" : ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file) }

extension UserDefaults {
    /// Preferences for this run: the real ones, or a throwaway suite in `--demo` mode.
    static var app: UserDefaults { Store.demo ? UserDefaults(suiteName: "io.github.lakshhaybedi.NetMeter.demo")! : .standard }
}

final class Store: NSObject, ObservableObject {
    @Published var nets: Days = [:]
    @Published var apps: Days = [:]
    @Published var down = 0.0
    @Published var up = 0.0
    @Published var network = "—"
    @Published var paused = false
    @Published var budgets: [String: Double] = [:]   // network -> GB/month
    @Published var layout = Store.loadLayout()
    @Published var scope = Scope(rawValue: UserDefaults.app.string(forKey: "scope") ?? "") ?? .all {
        didSet { UserDefaults.app.set(scope.rawValue, forKey: "scope") }
    }
    @Published var pins: [PinnedApp] = []            // apps tracked on their own line
    @Published var cycleDays: [String: Int] = [:]    // network → day of month its billing cycle resets (default 1)
    @Published var symbols: [String: String] = [:]   // network → SF Symbol chosen by the user
    @Published var editingNetwork: String?           // panel shows the network editor
    @Published var mainEditing: String?              // main window shows the network editor sheet
    @Published var baselines: [String: Int64] = [:]   // "yyyy-MM|network" → bytes to add to the tracked month download (usage before NetMeter started counting)
    @Published var aliases: [String: String] = [:]   // network name macOS reported → the network it counts as
    @Published var hiddenNets: Set<String> = []   // hidden (by group name) from every view and total; the data is kept
    @Published var hiddenApps: Set<String> = []
    @Published var downHist = [Double](repeating: 0, count: 60)
    @Published var upHist = [Double](repeating: 0, count: 60)
    var paths: [String: String] = [:]   // app name -> .app bundle path, for icons
    private var icons: [String: NSImage] = [:]
    var notified: Set<String> = []

    private var prev: [String: (UInt32, UInt32)] = [:]
    private var prevT = Date()
    private var lastSSID = UserDefaults.app.string(forKey: "lastSSID")   // survives restarts, so a hidden SSID never splits a network
    private var wifiIface: String?
    private var tickCount = 0
    private var ifaceWin = (i: UInt64(0), o: UInt64(0))   // exact interface bytes since the last per-app poll
    private var speedWin = (i: UInt64(0), o: UInt64(0))   // … since the last speed reading
    private var recent: [String: (i: Double, o: Double)] = [:]   // decaying per-app activity, to attribute bytes no snapshot saw
    private var streams: [Nettop] = []
    private var names: [String: String] = [:]
    private let loc = CLLocationManager()
    @Published var locationStatus = CLAuthorizationStatus.notDetermined
    @Published var notifStatus = UNAuthorizationStatus.notDetermined
    var locationAllowed: Bool { locationStatus == .authorizedAlways || locationStatus == .authorized }
    var dataFolder: URL { file.deletingLastPathComponent() }
    private let file: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NetMeter")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("data.json")
    }()
    static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    override init() {
        super.init()
        if Self.demo { loadDemo(); return }   // synthetic, in-memory: no timers, no streams, nothing read or written
        load()
        loc.delegate = self; locationStatus = loc.authorizationStatus
        refreshNotifStatus()
        if UserDefaults.app.bool(forKey: "onboarded") { requestLocation(); requestNotifications() }   // new users are asked from the welcome screen instead
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.5   // lets macOS coalesce wake-ups
        startStreams()
        let saver = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.save() }
        saver.tolerance = 10
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.save(); self?.streams.forEach { $0.stop() } }
    }

    private func load() {
        guard let d = try? Data(contentsOf: file) else { return }
        guard let s = try? JSONDecoder().decode(Saved.self, from: d) else {
            // never overwrite history we couldn't read: keep a copy beside it
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? FileManager.default.copyItem(at: file, to: dataFolder.appendingPathComponent("data-unreadable-\(stamp).json"))
            return
        }
        nets = s.nets; apps = s.apps; notified = s.notified; paths = s.paths ?? [:]; budgets = s.budgets ?? [:]
        hiddenNets = Set(s.hiddenNets ?? []); hiddenApps = Set(s.hiddenApps ?? [])
        baselines = s.baselines ?? [:]; aliases = s.aliases ?? [:]
        cycleDays = s.cycleDays ?? [:]; symbols = s.symbols ?? [:]; pins = s.pinned ?? []
    }

    func save() {
        guard !Self.demo else { return }
        let cutoff = Self.dayFmt.string(from: Date().addingTimeInterval(-400 * 86400))   // keep ~13 months
        if nets.keys.contains(where: { $0 < cutoff }) || apps.keys.contains(where: { $0 < cutoff }) {
            nets = nets.filter { $0.key >= cutoff }; apps = apps.filter { $0.key >= cutoff }
        }
        let s = Saved(nets: nets, apps: apps, notified: notified, paths: paths, budgets: budgets, hiddenNets: Array(hiddenNets), hiddenApps: Array(hiddenApps), aliases: aliases, baselines: baselines, cycleDays: cycleDays, symbols: symbols, pinned: pins)
        try? JSONEncoder().encode(s).write(to: file, options: .atomic)   // a crash mid-write must not corrupt the history
    }

    func group(_ n: String) -> String { aliases[n] ?? n }
    var rawNetworkNames: [String] { Set(nets.values.flatMap { $0.keys }).union(aliases.keys).sorted() }
    var networkGroups: [String] { Set(rawNetworkNames.map(group)).sorted() }

    /// Merges names that count as one (`group`), drops hidden ones, and rewrites i/o for the chosen scope.
    private func view(_ data: Days, hidden: Set<String>, group: ((String) -> String)? = nil, _ scope: Scope) -> Days {
        if hidden.isEmpty && scope == .all && group == nil { return data }
        return data.mapValues { m in
            var r: [String: Bytes] = [:]
            for (n, b) in m { let g = group?(n) ?? n; if !hidden.contains(g) { r[g, default: Bytes()].add(b.scoped(scope)) } }
            return r
        }
    }
    var visNets: Days { view(nets, hidden: hiddenNets, group: group, scope) }
    var visApps: Days { view(apps, hidden: hiddenApps, scope) }
    /// Internet-only networks regardless of the chosen view: what the ISP meters, so alerts and budgets use it.
    var inetNets: Days { view(nets, hidden: hiddenNets, group: group, .internet) }

    func detail(_ b: Bytes) -> String {
        "↓ \(fmt(b.i))  ↑ \(fmt(b.o))" + (scope == .all && b.local > 0 ? " · \(fmt(b.local)) local" : "")
    }

    func hide(_ name: String, net: Bool) { if net { hiddenNets.insert(name) } else { hiddenApps.insert(name) }; save() }
    func unhide(_ name: String, net: Bool) { if net { hiddenNets.remove(name) } else { hiddenApps.remove(name) }; save() }

    func reset() { nets = [:]; apps = [:]; notified = []; save() }

    func exportCSV() {
        // Wi-Fi names can be set by anyone nearby, so a cell must never start a spreadsheet formula
        func cell(_ t: String) -> String {
            let safe = (t.first.map { "=+-@\t\r".contains($0) } ?? false) ? "'" + t : t
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var out = "date,kind,name,bytes_in,bytes_out,local_bytes_in,local_bytes_out\n"
        for (kind, data) in [("network", nets), ("app", apps)] {
            for day in data.keys.sorted() {
                for (n, b) in data[day]!.sorted(by: { $0.key < $1.key }) { out += "\(day),\(kind),\(cell(n)),\(b.i),\(b.o),\(b.li),\(b.lo)\n" }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        let p = NSSavePanel(); p.nameFieldStringValue = "netmeter-usage.csv"; p.allowedContentTypes = [.commaSeparatedText]
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try out.write(to: u, atomically: true, encoding: .utf8) } catch { NSAlert(error: error).runModal() }
    }

    func icon(_ name: String) -> NSImage {
        if let i = icons[name] { return i }
        guard let p = paths[name] else { return NSWorkspace.shared.icon(for: .unixExecutable) }   // not cached: path may appear later
        let i = NSWorkspace.shared.icon(forFile: p); icons[name] = i; return i
    }

    /// Icon of the first app whose name contains `word`, or nil.
    func icon(matching word: String) -> NSImage? {
        paths.keys.sorted().first { $0.localizedCaseInsensitiveContains(word) }.map(icon)
    }

    // MARK: billing cycles (per network)

    /// Start of the network's current billing cycle: the most recent occurrence of its reset day (1–28).
    func cycleStart(_ network: String) -> Date { BillingCycle.start(day: cycleDays[network] ?? 1) }
    func cycleStartKey(_ network: String) -> String { Self.dayFmt.string(from: cycleStart(network)) }
    func cycleReset(_ network: String) -> Date { Calendar.current.date(byAdding: .month, value: 1, to: cycleStart(network))! }
    func baselineKey(_ network: String) -> String { cycleStartKey(network) + "|" + network }

    /// Bytes on one network since its cycle started.
    /// The baseline (usage from before NetMeter was counting, set from the ISP's figure) belongs to cycle totals only, so it
    /// never appears as a fake spike in daily charts or history.
    func cycleBytes(_ network: String, in data: Days, baseline: Bool = true) -> Bytes {
        let start = cycleStartKey(network)
        var r = data.reduce(into: Bytes()) { r, e in if e.key >= start, let b = e.value[network] { r.add(b) } }
        if baseline, let base = baselines[baselineKey(network)] { r.i = UInt64(max(Int64(r.i) + base, 0)) }
        return r
    }

    /// Per-network totals for a period; "Month" means each network's own billing cycle.
    func netSums(_ data: Days, _ p: Period, baseline: Bool? = nil) -> [(name: String, b: Bytes)] {
        guard p == .month else { return sums(data, p) }
        let withBase = baseline ?? (scope != .local)   // the baseline is internet download, so it doesn't belong in the Local view
        let names = Set(data.values.flatMap { $0.keys }).union(withBase ? baselines.keys.compactMap { k -> String? in
            let p = k.split(separator: "|", maxSplits: 1).map(String.init); return p.count == 2 && p[0] == cycleStartKey(p[1]) && !hiddenNets.contains(p[1]) ? p[1] : nil } : [])
        return names.map { ($0, cycleBytes($0, in: data, baseline: withBase)) }.filter { $0.1.total > 0 }.sorted { $0.1.total > $1.1.total }
    }

    /// Internet download in the current cycle: the figure an ISP meters (tracked bytes plus the baseline).
    func monthDownload(_ network: String) -> UInt64 { cycleBytes(network, in: inetNets).i }

    /// Re-sync with the ISP's own meter: the baseline becomes whatever makes this cycle's download equal `gb`.
    func setMonthUsed(_ network: String, gb: Double) {
        let tracked = Int64(cycleBytes(network, in: inetNets, baseline: false).i)
        baselines[baselineKey(network)] = Int64(gb * 1e9) - tracked
        checkMilestones(silent: true)   // thresholds already passed shouldn't fire a burst of alerts
        save()
    }

    /// "119.78 GB of 3,300 GB used this month"; a custom reset day says "this cycle".
    func monthUsed(_ network: String) -> String {
        "\(fmt(monthDownload(network)))" + (budgets[network].map { " of \($0.formatted()) GB" } ?? "") + " used this " + ((cycleDays[network] ?? 1) == 1 ? "month" : "cycle")
    }

    func symbol(_ network: String) -> String { symbols[network] ?? (network.hasPrefix("Wired") ? "cable.connector" : "wifi") }

    var today: String { Self.dayFmt.string(from: Date()) }

    // MARK: sampling

    private func counters() -> [String: (UInt32, UInt32)] {
        var out: [String: (UInt32, UInt32)] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return out }
        defer { freeifaddrs(head) }
        var c = head
        while let a = c {
            let n = String(cString: a.pointee.ifa_name)
            if n.hasPrefix("en"), let sa = a.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK), let d = a.pointee.ifa_data {
                let s = d.assumingMemoryBound(to: if_data.self).pointee
                out[n] = (s.ifi_ibytes, s.ifi_obytes)   // ponytail: 32-bit counters, wraps once per 4GB; fine at a 2s tick
            }
            c = a.pointee.ifa_next
        }
        return out
    }

    private func tick() {
        let now = Date(), dt = max(now.timeIntervalSince(prevT), 0.1); prevT = now
        tickCount += 1
        if tickCount % 5 == 1 {   // CoreWLAN is an XPC round trip; the network rarely changes, so ask every ~10 s
            let wifi = CWWiFiClient.shared().interface()
            if let n = wifi?.ssid(), n != lastSSID { lastSSID = n; UserDefaults.app.set(n, forKey: "lastSSID") }   // macOS sometimes withholds the SSID; keep the last good one
            wifiIface = wifi?.interfaceName
            let net = wifi?.powerOn() == true ? group(netLabel(wifiIface ?? "")) : "Offline/Wired"
            if net != network { network = net }
        }
        sampleInterfaces()
        down = Double(speedWin.i) / dt; up = Double(speedWin.o) / dt
        let moved = speedWin.i + speedWin.o; speedWin = (0, 0)
        downHist.removeFirst(); downHist.append(down); upHist.removeFirst(); upHist.append(up)
        if moved > 0 { checkMilestones() }
    }

    /// Reads the interface counters now and books the bytes since the last read. Also called at each per-app poll,
    /// so the exact interface window lines up with the poll's snapshot.
    private func sampleInterfaces() {
        let cur = counters(), d = today
        for (n, v) in cur where !paused {
            if let p = prev[n] {
                let i = UInt64(v.0 &- p.0), o = UInt64(v.1 &- p.1)
                if i + o > 0 {
                    nets[d, default: [:]][netLabel(n), default: Bytes()].add(Bytes(i: i, o: o))
                    ifaceWin.i += i; ifaceWin.o += o; speedWin.i += i; speedWin.o += o
                }
            }
        }
        prev = cur
    }

    private func netLabel(_ iface: String) -> String { iface == wifiIface ? (lastSSID ?? "Wi-Fi") : "Wired/Other (\(iface))" }

    /// Per-app sampling interval in seconds (Settings → Performance); each poll costs ~30 ms of CPU.
    static var pollSeconds: TimeInterval { let v = UserDefaults.app.double(forKey: "appPoll"); return v >= 1 ? v : 5 }

    private func startStreams() {
        streams = [Nettop(delay: { Store.pollSeconds }) { [weak self] rows, first in self?.apply(rows, first) }]
    }

    /// Each row is one live connection's new bytes: split into internet, home network (LAN) and this Mac (loopback).
    private func apply(_ rows: [NetRow], _ first: Bool) {
        // names must be resolved while the process is alive
        var alive = Set<String>()
        for r in rows { alive.insert(r.proc); _ = appName(r.proc) }
        names = names.filter { alive.contains($0.key) }
        sampleInterfaces()
        let win = ifaceWin; ifaceWin = (0, 0)
        guard !first, !paused else { return }   // the first poll only seeds the counters
        let d = today
        var a = apps[d] ?? [:], n = nets[d] ?? [:], lanSeen = false
        var seen = (i: UInt64(0), o: UInt64(0)), lanBytes = (i: UInt64(0), o: UInt64(0)), share: [String: (i: UInt64, o: UInt64)] = [:]
        for r in rows where r.i + r.o > 0 {
            let app = appName(r.proc)
            a[app, default: Bytes()].i += r.i; a[app, default: Bytes()].o += r.o
            let loop = r.iface == "lo0"
            let lan = !loop && r.iface.hasPrefix("en") && Nettop.isLAN(r.remote)   // VPN tunnels (utun) carry internet
            if loop || lan { a[app, default: Bytes()].li += r.i; a[app, default: Bytes()].lo += r.o }
            if lan {
                lanSeen = true; lanBytes.i += r.i; lanBytes.o += r.o
                let net = netLabel(r.iface); n[net, default: Bytes()].li += r.i; n[net, default: Bytes()].lo += r.o
            } else if r.iface.hasPrefix("en") {
                seen.i += r.i; seen.o += r.o
                share[app, default: (0, 0)].i += r.i; share[app, default: (0, 0)].o += r.o
            }
        }
        // Bytes a connection moved after our last look and before it closed are invisible to a snapshot, but the interface
        // counters saw them. Hand that remainder to the apps that were recently active (weighted), else "Unattributed".
        let missI = win.i > lanBytes.i + seen.i ? win.i - lanBytes.i - seen.i : 0
        let missO = win.o > lanBytes.o + seen.o ? win.o - lanBytes.o - seen.o : 0
        for k in recent.keys { recent[k] = (recent[k]!.i * 0.6, recent[k]!.o * 0.6) }
        for (app, v) in share { recent[app, default: (0, 0)].i += Double(v.i); recent[app, default: (0, 0)].o += Double(v.o) }
        recent = recent.filter { $0.value.i + $0.value.o > 1 }
        let wi = recent.values.reduce(0) { $0 + $1.i }, wo = recent.values.reduce(0) { $0 + $1.o }
        if missI > 0 {
            if wi > 1000 { for (app, w) in recent { a[app, default: Bytes()].i += UInt64(Double(missI) * w.i / wi) } }
            else { a["Unattributed", default: Bytes()].i += missI }
        }
        if missO > 0 {
            if wo > 1000 { for (app, w) in recent { a[app, default: Bytes()].o += UInt64(Double(missO) * w.o / wo) } }
            else { a["Unattributed", default: Bytes()].o += missO }
        }
        apps[d] = a
        if lanSeen { nets[d] = n }
    }

    // nettop truncates names to 15 chars; resolve the real executable and group helpers under their
    // outermost .app, so Docker's backend/VM/helpers all count as "Docker".
    private func appName(_ token: String) -> String {
        if let n = names[token] { return n }
        guard let dot = token.lastIndex(of: "."), let pid = Int32(token[token.index(after: dot)...]) else { return token }
        let short = String(token[..<dot])
        var b = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &b, UInt32(b.count)) > 0 else { return short }
        let path = String(cString: b)
        let base = path.range(of: ".app/").map { String(path[..<$0.lowerBound]) } ?? path
        let name = (base as NSString).lastPathComponent
        if base != path, paths[name] == nil { paths[name] = base + ".app" }
        names[token] = name
        return name
    }

    // MARK: aggregation

    func sums(_ data: Days, _ period: Period) -> [(name: String, b: Bytes)] {
        let t = today
        let start: String
        switch period {
        case .day: start = t
        case .month: start = String(t.prefix(7)) + "-01"
        case .week:
            let c = Calendar.current
            start = Self.dayFmt.string(from: c.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
        }
        var r: [String: Bytes] = [:]
        for (day, m) in data where day >= start { for (n, b) in m { r[n, default: Bytes()].add(b) } }
        return r.map { ($0.key, $0.value) }.sorted { $0.b.total > $1.b.total }
    }

    func total(_ data: Days, _ p: Period) -> UInt64 { sums(data, p).reduce(0) { $0 + $1.b.total } }

    // MARK: milestones

    private func checkMilestones(silent: Bool = false) {
        let thresholds = (UserDefaults.app.string(forKey: "thresholds") ?? "1,5,10,25,50,100")
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        for (name, _) in netSums(inetNets, .month, baseline: true) {
            let month = cycleStartKey(name)   // alerts re-arm when the cycle resets
            let used = monthDownload(name)
            for t in thresholds where Double(used) >= t * 1e9 {
                let key = "\(month)|\(name)|\(t)"
                guard notified.insert(key).inserted, !silent else { continue }
                let c = UNMutableNotificationContent()
                c.title = "\(name): \(t.formatted()) GB downloaded this month"
                c.body = "Used so far: \(fmt(used))"
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: c, trigger: nil))
            }
            if let gb = budgets[name], gb > 0 {
                for (pct, word) in [(0.8, "80% of"), (1.0, "over")] where Double(used) >= pct * gb * 1e9 {
                    let key = "\(month)|\(name)|budget\(pct)"
                    guard notified.insert(key).inserted, !silent else { continue }
                    let c = UNMutableNotificationContent()
                    c.title = "\(name) is \(word) its \(gb.formatted()) GB budget"
                    c.body = "Used \(fmt(used)) this month"
                    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: c, trigger: nil))
                }
            }
        }
    }

    // MARK: menu bar label
}

// MARK: permissions

extension Store: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { locationStatus = manager.authorizationStatus }

    /// Asks for Location (needed to read the Wi-Fi name); once macOS has decided, opens the System Settings pane instead.
    func requestLocation() {
        if locationStatus == .notDetermined { loc.requestWhenInUseAuthorization() }
        else { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!) }
    }

    func refreshNotifStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { st in DispatchQueue.main.async { self.notifStatus = st.authorizationStatus } }
    }

    func requestNotifications() {
        if notifStatus == .notDetermined {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in self.refreshNotifStatus() }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
        }
    }
}

/// A billing cycle starts on a fixed day of the month (1–28, so every month has it).
enum BillingCycle {
    /// Start (midnight) of the cycle containing `now`: the most recent occurrence of `day`.
    static func start(day: Int, now: Date = Date(), calendar cal: Calendar = .current) -> Date {
        var c = cal.dateComponents([.year, .month], from: now); c.day = min(max(day, 1), 28)
        let thisMonth = cal.date(from: c)!
        return cal.startOfDay(for: thisMonth <= now ? thisMonth : cal.date(byAdding: .month, value: -1, to: thisMonth)!)
    }
}
