import SwiftUI

enum SectionID: String, Codable, CaseIterable {
    case speed, networks, pinned, apps
    var title: String {
        switch self { case .speed: "Live traffic"; case .networks: "Networks"; case .pinned: "Pinned"; case .apps: "Apps" }
    }
    var symbol: String {
        switch self { case .speed: "waveform.path.ecg"; case .networks: "network"; case .pinned: "star.fill"; case .apps: "square.grid.2x2" }
    }
    var isList: Bool { self != .speed }
}

enum Size: String, Codable, CaseIterable {
    case s, m, l
    var name: String { switch self { case .s: "Small"; case .m: "Medium"; case .l: "Large" } }
    var icon: CGFloat { switch self { case .s: 18; case .m: 26; case .l: 34 } }
    var gap: CGFloat { switch self { case .s: 6; case .m: 10; case .l: 14 } }
    var chart: CGFloat { switch self { case .s: 28; case .m: 46; case .l: 96 } }
}

struct SectionCfg: Codable, Identifiable {
    var id: SectionID
    var size = Size.m
    var limit = 6          // max rows (list sections)
    var collapsed = false
    var hidden = false
}

extension Store {
    static let layoutKey = "layout"

    static func loadLayout() -> [SectionCfg] {
        var l = UserDefaults.app.data(forKey: layoutKey).flatMap { try? JSONDecoder().decode([SectionCfg].self, from: $0) } ?? []
        for id in SectionID.allCases where !l.contains(where: { $0.id == id }) {   // new sections appear at the end
            l.append(SectionCfg(id: id, limit: id == .apps ? 6 : 5))
        }
        return l
    }

    func saveLayout() { UserDefaults.app.set(try? JSONEncoder().encode(layout), forKey: Self.layoutKey) }

    func update(_ id: SectionID, _ f: (inout SectionCfg) -> Void) {
        guard let i = layout.firstIndex(where: { $0.id == id }) else { return }
        f(&layout[i]); saveLayout()
    }

    func bind<T>(_ id: SectionID, _ kp: WritableKeyPath<SectionCfg, T>) -> Binding<T> {
        Binding { self.layout.first { $0.id == id }![keyPath: kp] } set: { v in self.update(id) { $0[keyPath: kp] = v } }
    }

    /// Drop `id` onto `target`: takes the target's position, pushing the rest along.
    func move(_ id: SectionID, onto target: SectionID) {
        guard id != target, let f = layout.firstIndex(where: { $0.id == id }), let t = layout.firstIndex(where: { $0.id == target }) else { return }
        layout.insert(layout.remove(at: f), at: t); saveLayout()
    }

    func move(_ id: SectionID, by d: Int) {
        guard let f = layout.firstIndex(where: { $0.id == id }), (0..<layout.count).contains(f + d) else { return }
        layout.swapAt(f, f + d); saveLayout()
    }
}

/// Section chrome: draggable header (grip), size/rows/move/hide menu, collapse chevron, drop target.
struct SectionBox<Content: View>: View {
    @ObservedObject var s: Store
    let id: SectionID
    @ViewBuilder var content: Content
    @State private var targeted = false

    var cfg: SectionCfg { s.layout.first { $0.id == id }! }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal").font(.caption2).foregroundStyle(.tertiary).help("Drag to reorder").accessibilityHidden(true)
                SectionTitle(id.title, id.symbol)
                Spacer()
                Menu {
                    Picker("Size", selection: s.bind(id, \.size)) { ForEach(Size.allCases, id: \.self) { Text($0.name) } }
                    if id.isList {
                        Picker("Rows", selection: s.bind(id, \.limit)) { ForEach([3, 5, 8, 12, 25], id: \.self) { Text("\($0) rows").tag($0) } }
                    }
                    Divider()
                    Button("Move up") { s.move(id, by: -1) }
                    Button("Move down") { s.move(id, by: 1) }
                    Button("Hide section") { s.update(id) { $0.hidden = true } }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("\(id.title) options")
                Button { s.update(id) { $0.collapsed.toggle() } } label: {
                    Image(systemName: cfg.collapsed ? "chevron.right" : "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).help(cfg.collapsed ? "Expand" : "Collapse").accessibilityLabel(cfg.collapsed ? "Expand \(id.title)" : "Collapse \(id.title)")
            }
            .contentShape(Rectangle())
            .draggable(id.rawValue)
            if !cfg.collapsed { content }
        }
        .padding(6)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 2).opacity(targeted ? 1 : 0))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let from = SectionID(rawValue: raw) else { return false }
            s.move(from, onto: id); return true
        } isTargeted: { targeted = $0 }
    }
}
