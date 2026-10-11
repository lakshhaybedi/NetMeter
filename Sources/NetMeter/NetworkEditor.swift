import SwiftUI

/// Everything about one network in one place: limit, billing-cycle reset day, usage re-sync, icon, visibility, merged names.
/// Used inline in the menu bar panel, as a sheet in the main window, and from Settings.
struct NetworkEditor: View {
    @ObservedObject var s: Store
    let network: String
    var done: () -> Void
    @State private var used = ""

    static let icons: [(name: String, symbol: String)] = [
        ("Wi-Fi", "wifi"), ("Phone hotspot", "personalhotspot"), ("Home", "house"), ("Cellular", "antenna.radiowaves.left.and.right"), ("Wired", "cable.connector"),
    ]
    private static let ordinal: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .ordinal; return f }()
    private func ordinal(_ d: Int) -> String { Self.ordinal.string(from: NSNumber(value: d)) ?? "\(d)" }

    private var limit: Binding<Double?> { Binding { s.budgets[network] } set: { s.budgets[network] = ($0 ?? 0) > 0 ? $0 : nil } }
    private var cycleDay: Binding<Int> { Binding { s.cycleDays[network] ?? 1 } set: { s.cycleDays[network] = $0 == 1 ? nil : $0; s.save() } }
    private var symbol: Binding<String> { Binding { s.symbol(network) } set: { s.symbols[network] = $0; s.save() } }
    private var shown: Binding<Bool> { Binding { !s.hiddenNets.contains(network) } set: { on in on ? s.unhide(network, net: true) : s.hide(network, net: true) } }
    private var members: [String] { s.rawNetworkNames.filter { s.group($0) == network } }
    private var others: [String] { s.networkGroups.filter { $0 != network } }

    private func apply() {
        if let gb = Double(used.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)), gb >= 0 { s.setMonthUsed(network, gb: gb) }
        used = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: done) { Image(systemName: "chevron.left").frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .buttonStyle(.borderless).keyboardShortcut(.cancelAction).accessibilityLabel("Back")
                Image(systemName: s.symbol(network)).foregroundStyle(.secondary)
                Text(network).font(.headline).lineLimit(1)
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            Form {
                Section("Limit and billing cycle") {
                    LabeledContent("Monthly limit") {
                        HStack(spacing: 4) {
                            TextField("Limit", value: limit, format: .number, prompt: Text("None")).labelsHidden().multilineTextAlignment(.trailing).frame(width: 90)
                            Text("GB").foregroundStyle(.secondary)
                        }
                    }
                    Picker("Resets on the", selection: cycleDay) { ForEach(1...28, id: \.self) { Text(ordinal($0)).tag($0) } }
                    LabeledContent("Used this cycle") {
                        HStack(spacing: 4) {
                            TextField("Used", text: $used, prompt: Text(String(format: "%.2f", Double(s.monthDownload(network)) / 1e9)))
                                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 90).onSubmit(apply)
                            Text("GB").foregroundStyle(.secondary)
                            Button("Set", action: apply).disabled(Double(used.replacingOccurrences(of: ",", with: ".")) == nil)
                        }
                    }
                    Text("Counting since \(s.cycleStart(network).formatted(.dateTime.day().month(.abbreviated))); resets \(s.cycleReset(network).formatted(.dateTime.day().month(.abbreviated))). Enter the figure from your ISP's usage page and press Set to re-sync.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Appearance") {
                    Picker("Icon", selection: symbol) { ForEach(Self.icons, id: \.symbol) { Label($0.name, systemImage: $0.symbol).tag($0.symbol) } }
                    Toggle("Show in lists", isOn: shown)
                }
                Section("Names counted as this network") {
                    ForEach(members, id: \.self) { n in
                        LabeledContent(n) {
                            if n != network { Button("Remove") { s.aliases[n] = nil; s.save() }.buttonStyle(.borderless) }
                        }
                    }
                    if !others.isEmpty {
                        Menu("Add another network…") {
                            ForEach(others, id: \.self) { g in Button(g) { for raw in s.rawNetworkNames where s.group(raw) == g { s.aliases[raw] = network }; s.save() } }
                        }
                    }
                }
            }
            .formStyle(.grouped).scrollContentBackground(.hidden)
        }
        .onDisappear { s.save() }
    }
}
