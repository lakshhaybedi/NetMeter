import Foundation

/// Bytes moved by one live connection since the previous poll.
struct NetRow {
    let proc: String      // "name.pid" (name truncated by nettop)
    let remote: String    // peer address without port
    let iface: String     // en0, lo0, utun4, …
    let i: UInt64, o: UInt64
}

/// Polls a one-shot `nettop` (a snapshot of every live socket with its lifetime byte counts) and reports per-connection
/// deltas. nettop's streaming mode keeps a kernel subscription open and burns >100% CPU; a snapshot costs ~30 ms.
/// Diffing per connection (not per process) avoids negative/double counts when sockets close. Traffic on a connection
/// that opens and closes between two polls is missed; the interface counters stay exact regardless.
final class Nettop {
    private let delay: () -> TimeInterval
    private let onPoll: ([NetRow], _ first: Bool) -> Void
    private var prev: [String: (UInt64, UInt64)]?
    private var stopped = false

    init(delay: @escaping () -> TimeInterval, onPoll: @escaping ([NetRow], Bool) -> Void) {
        self.delay = delay; self.onPoll = onPoll; schedule(after: 0.5)
    }

    func stop() { stopped = true }

    private func schedule(after t: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in self?.poll() }
    }

    private func poll() {
        guard !stopped else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snap = Self.snapshot()
            DispatchQueue.main.async { guard let self else { return }; self.deliver(snap); self.schedule(after: self.delay()) }
        }
    }

    private func deliver(_ snap: [(key: String, row: NetRow)]) {
        let first = prev == nil
        var cur: [String: (UInt64, UInt64)] = [:], out: [NetRow] = []
        for (key, r) in snap {
            cur[key] = (r.i, r.o)
            if first { out.append(NetRow(proc: r.proc, remote: r.remote, iface: r.iface, i: 0, o: 0)); continue }
            let p = prev?[key] ?? (0, 0)   // a connection we haven't seen opened since the last poll: all of it is new
            out.append(NetRow(proc: r.proc, remote: r.remote, iface: r.iface,
                              i: r.i >= p.0 ? r.i - p.0 : r.i, o: r.o >= p.1 ? r.o - p.1 : r.o))
        }
        prev = cur
        onPoll(out, first)
    }

    private static func snapshot() -> [(key: String, row: NetRow)] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        p.arguments = ["-L", "1", "-s", "1", "-n", "-x", "-J", "interface,state,bytes_in,bytes_out"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        var proc = "", rows: [(key: String, row: NetRow)] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n").dropFirst() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 5 else { continue }
            let name = String(f[0])
            guard name.contains("<->") else { proc = name; continue }      // process row: remember who owns the rows below
            guard let i = UInt64(f[3]), let o = UInt64(f[4]) else { continue }   // listeners have no bytes
            rows.append((proc + "|" + name, NetRow(proc: proc, remote: remote(name), iface: String(f[1]), i: i, o: o)))
        }
        return rows
    }

    /// "tcp4 192.168.0.5:51000<->17.1.2.3:443" → "17.1.2.3"; IPv6 rows separate the port with ".".
    static func remote(_ row: String) -> String {
        let r = row.components(separatedBy: "<->").last ?? ""
        let v6 = row.hasPrefix("tcp6") || row.hasPrefix("udp6")
        return String(r[..<(r.lastIndex(of: v6 ? "." : ":") ?? r.endIndex)])
    }

    /// Home-network / link-local / multicast peers: traffic that never reaches the ISP.
    static func isLAN(_ a: String) -> Bool {
        if a.contains(":") { let l = a.lowercased(); return l.hasPrefix("fe80") || l.hasPrefix("fc") || l.hasPrefix("fd") || l.hasPrefix("ff") }
        let p = a.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }   // "*" (unconnected UDP) and anything unparseable counts as internet
        switch (p[0], p[1]) {
        case (10, _), (192, 168), (169, 254), (172, 16...31), (224...239, _), (255, _): return true
        default: return false
        }
    }
}
