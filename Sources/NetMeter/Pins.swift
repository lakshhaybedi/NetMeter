import SwiftUI

/// An app (or command-line tool) the user wants tracked on its own line in the panel.
struct PinnedApp: Codable, Identifiable, Hashable {
    var name: String
    var exact = true      // true: exactly this app/tool; false: any app whose name contains `name` (older text-based pins)
    var path: String?     // the .app bundle, for its icon
    var id: String { (exact ? "=" : "~") + name.lowercased() }

    func matches(_ app: String) -> Bool {
        exact ? app.caseInsensitiveCompare(name) == .orderedSame : app.localizedCaseInsensitiveContains(name)
    }

    /// From a Finder pick: an .app bundle becomes its bundle name (what NetMeter calls it); anything else, its file name.
    static func from(_ url: URL) -> PinnedApp {
        let path = url.path
        if let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) {
            let base = String(path[..<r.lowerBound])   // the outermost bundle, like process grouping does
            return PinnedApp(name: (base as NSString).lastPathComponent, exact: true, path: base + ".app")
        }
        return PinnedApp(name: url.lastPathComponent, exact: true, path: nil)
    }
}

extension Store {
    func addPins(_ list: [PinnedApp]) {
        for p in list where !pins.contains(where: { $0.id == p.id }) { pins.append(p) }
        save()
    }
    func removePin(_ p: PinnedApp) { pins.removeAll { $0.id == p.id }; save() }

    func isPinned(_ app: String) -> Bool { pins.contains { $0.matches(app) } }

    /// The ☆ in the apps list: unpins every entry that covers the app, or pins it exactly.
    func togglePin(_ app: String) {
        if isPinned(app) { pins.removeAll { $0.matches(app) } } else { pins.append(PinnedApp(name: app, exact: true, path: paths[app])) }
        save()
    }

    /// Usage per tracked app for a period (all processes it covers, summed).
    func pinnedUsage(_ p: Period) -> [(app: PinnedApp, b: Bytes)] {
        let all = sums(visApps, p)
        return pins.map { pin in
            var t = Bytes()
            for a in all where pin.matches(a.name) { t.add(a.b) }
            return (pin, t)
        }
    }

    func pinIcon(_ p: PinnedApp) -> NSImage? {
        p.path.map { NSWorkspace.shared.icon(forFile: $0) } ?? icon(matching: p.name)
    }

    func smallIcon(_ name: String) -> NSImage {
        let i = (icon(name).copy() as? NSImage) ?? icon(name); i.size = NSSize(width: 16, height: 16); return i
    }
}
