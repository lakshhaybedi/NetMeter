import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement
import UserNotifications
import CoreLocation

/// Keeps the app out of the Dock until one of its windows is open (it's a menu bar app otherwise).
@MainActor enum WindowPolicy {
    private static var open = 0
    static func opened() { open += 1; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    static func closed() { open = max(0, open - 1); if open == 0 { NSApp.setActivationPolicy(.accessory) } }
}

/// Section footer, left-aligned like System Settings.
struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsRoot: View {
    @ObservedObject var s: Store
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralPane(s: s) }
            Tab("Menu Bar", systemImage: "menubar.rectangle") { MenuBarPane(s: s) }
            Tab("Networks", systemImage: "wifi") { NetworksPane(s: s) }
            Tab("Apps", systemImage: "square.grid.2x2") { AppsPane(s: s) }
            Tab("Alerts", systemImage: "bell") { AlertsPane() }
            Tab("Data", systemImage: "externaldrive") { DataPane(s: s) }
        }
        .frame(width: 580, height: 540)
        .onAppear { WindowPolicy.opened() }
        .onDisappear { WindowPolicy.closed() }
    }
}

// MARK: General

struct GeneralPane: View {
    @ObservedObject var s: Store
    @AppStorage("appPoll") private var appPoll = 5.0
    @State private var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open NetMeter at login", isOn: $login)
                    .onChange(of: login) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { login = SMAppService.mainApp.status == .enabled }
                    }
            }
            Section {
                Picker("Show", selection: $s.scope) { ForEach(Scope.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
            } header: { Text("Traffic") } footer: { Note("Internet is what your ISP meters. Local stays on this Mac (for example Docker to rclone) or goes to devices on your home network. Limits, alerts and “used this month” always use internet download.")
            }
            Section {
                Picker("Per-app sampling", selection: $appPoll) {
                    Text("Every 2 seconds").tag(2.0); Text("Every 5 seconds").tag(5.0); Text("Every 15 seconds").tag(15.0); Text("Every 30 seconds").tag(30.0)
                }
            } header: { Text("Performance") } footer: { Note("Each sample costs about 30 ms of CPU. Slower sampling saves energy but can miss connections that open and close in between. Network totals and “used this month” are exact at any setting.")
            }
            Section("Permissions") {
                LabeledContent("Location") {
                    HStack { Text(s.locationAllowed ? "Allowed" : "Not allowed").foregroundStyle(s.locationAllowed ? Color.secondary : Color.orange)
                        if !s.locationAllowed { Button(s.locationStatus == .notDetermined ? "Allow…" : "Open System Settings…") { s.requestLocation() } } }
                }
                Text("macOS only reveals the Wi-Fi network name to apps with Location access. Without it, usage can't be told apart by network.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Notifications") {
                    HStack { Text(s.notifStatus == .authorized ? "Allowed" : "Not allowed").foregroundStyle(s.notifStatus == .authorized ? Color.secondary : Color.orange)
                        if s.notifStatus != .authorized { Button(s.notifStatus == .notDetermined ? "Allow…" : "Open System Settings…") { s.requestNotifications() } } }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Menu bar & panel

struct MenuBarPane: View {
    @ObservedObject var s: Store
    @AppStorage("items") private var items = "Used this month"
    @AppStorage("showIcons") private var showIcons = true
    @AppStorage("showBars") private var showBars = true
    @AppStorage("showDetail") private var showDetail = true
    @AppStorage("showSubtitle") private var showSubtitle = true
    @AppStorage("showFooter") private var showFooter = true
    @AppStorage("barStyle") private var barStyle = BarStyle.both
    @AppStorage("barIcon") private var barIcon = "arrow.up.arrow.down.circle.fill"
    @AppStorage("barNumbers") private var barNumbers = NumberStyle.compact
    @AppStorage("barStacked") private var barStacked = false
    @AppStorage("collapseOtherNets") private var collapseOthers = true

    private var enabled: [Item] { items.split(separator: ",").compactMap { Item(rawValue: String($0)) } }
    private func setEnabled(_ l: [Item]) { items = l.map(\.rawValue).joined(separator: ",") }
    private func binding(_ it: Item) -> Binding<Bool> {
        Binding { enabled.contains(it) } set: { on in setEnabled(on ? enabled + (enabled.contains(it) ? [] : [it]) : enabled.filter { $0 != it }) }
    }
    private func move(_ it: Item, _ d: Int) {
        var l = enabled
        guard let i = l.firstIndex(of: it), (0..<l.count).contains(i + d) else { return }
        l.swapAt(i, i + d); setEnabled(l)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Preview") {
                    BarContent(s: s).foregroundStyle(.primary).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                Picker("Show", selection: $barStyle) { ForEach(BarStyle.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Icon", selection: $barIcon) { ForEach(BarIcons.all, id: \.symbol) { Label($0.name, systemImage: $0.symbol).tag($0.symbol) } }
                    .disabled(barStyle == .text)
                Picker("Numbers", selection: $barNumbers) { ForEach(NumberStyle.allCases) { Text("\($0.rawValue)  (\($0.example))").tag($0) } }
                Toggle("Stack on two lines", isOn: $barStacked)
            } header: { Text("Menu bar item") } footer: {
                Note("Compact and tiny numbers, or two lines, keep the item short. The icon is always shown when no text is selected, so the item never disappears.")
            }
            Section {
                ForEach(enabled + Item.allCases.filter { !enabled.contains($0) }, id: \.self) { it in
                    HStack {
                        Toggle(it.rawValue, isOn: binding(it))
                        if enabled.contains(it) {
                            Spacer()
                            Button { move(it, -1) } label: { Image(systemName: "chevron.up") }.accessibilityLabel("Move \(it.rawValue) up")
                            Button { move(it, 1) } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Move \(it.rawValue) down")
                        }
                    }.buttonStyle(.borderless)
                }
            } header: { Text("Menu bar shows") } footer: { Note("Items appear in this order.") }
            Section {
                ForEach(s.layout) { c in
                    HStack(spacing: 8) {
                        Button { s.move(c.id, by: -1) } label: { Image(systemName: "chevron.up") }.accessibilityLabel("Move \(c.id.title) up")
                        Button { s.move(c.id, by: 1) } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Move \(c.id.title) down")
                        Label(c.id.title, systemImage: c.id.symbol).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Picker("Size", selection: s.bind(c.id, \.size)) { ForEach(Size.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) } }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 100)
                        if c.id.isList {
                            HStack(spacing: 6) {
                                Text("\(c.limit)").monospacedDigit().frame(width: 26, alignment: .trailing)
                                Stepper("Rows", value: s.bind(c.id, \.limit), in: 1...25).labelsHidden()
                            }.help("Maximum rows")
                        }
                        Toggle("Visible", isOn: Binding { !c.hidden } set: { on in s.update(c.id) { $0.hidden = !on } }).labelsHidden()
                    }.buttonStyle(.borderless)
                }
            } header: { Text("Panel sections") } footer: { Note("You can also drag a section by its ≡ handle in the panel, or use its ⋯ menu.") }
            Section("Panel appearance") {
                Toggle("App and network icons", isOn: $showIcons)
                Toggle("Usage bars", isOn: $showBars)
                Toggle("Download / upload detail line", isOn: $showDetail)
                Toggle("Header summary line", isOn: $showSubtitle)
                Toggle("Footer total", isOn: $showFooter)
                Toggle("Only show the connected network; others in a dropdown", isOn: $collapseOthers)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Networks

struct NetworksPane: View {
    @ObservedObject var s: Store
    @State private var editing: String?

    private func alias(_ n: String) -> Binding<String> {
        Binding { s.aliases[n] ?? "" } set: { v in
            let t = v.trimmingCharacters(in: .whitespaces)
            s.aliases[n] = (t.isEmpty || t == n) ? nil : t
        }
    }
    private func summary(_ g: String) -> String {
        var parts: [String] = []
        if let gb = s.budgets[g] { parts.append("\(gb.formatted()) GB") }
        if let d = s.cycleDays[g] { parts.append("resets on the \(d)\(d % 10 == 1 && d != 11 ? "st" : d % 10 == 2 && d != 12 ? "nd" : d % 10 == 3 && d != 13 ? "rd" : "th")") }
        if s.hiddenNets.contains(g) { parts.append("hidden") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 0) {
                    let groups = s.networkGroups
                    if groups.isEmpty { Text("Networks appear here once traffic is recorded.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(Array(groups.enumerated()), id: \.element) { i, g in
                        if i > 0 { Divider().padding(.vertical, 6) }
                        HStack {
                            Label(g, systemImage: s.symbol(g)).lineLimit(1)
                            Spacer()
                            Text(summary(g)).foregroundStyle(.secondary)
                            Button("Edit…") { editing = g }
                        }
                    }
                }
            } header: { Text("Networks") } footer: { Note("Each network has its own monthly limit and billing-cycle reset day. You can also right-click a network in the panel or main window.")
            }
            Section {
                ForEach(s.rawNetworkNames, id: \.self) { n in
                    LabeledContent(n) { TextField(n, text: alias(n), prompt: Text(n)).labelsHidden().multilineTextAlignment(.trailing).frame(width: 180) }
                }
            } header: { Text("Names macOS reported") } footer: { Note("Give several names the same “counts as” name to merge them, for example a router's 2.4 and 5 GHz networks, or the generic “Wi-Fi” shown while macOS hides the name.")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let n = editing { NetworkEditor(s: s, network: n, done: { editing = nil }).padding().frame(width: 460, height: 560) }
        }
    }
}

// MARK: Apps & alerts

struct AppsPane: View {
    @ObservedObject var s: Store
    @State private var keyword = ""

    private func choose() {
        let p = NSOpenPanel()
        p.title = "Choose apps to track"; p.message = "Pick apps, or command-line tools such as rclone."; p.prompt = "Add"
        p.allowedContentTypes = [.application, .unixExecutable]
        p.allowsMultipleSelection = true; p.canChooseDirectories = false
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK { s.addPins(p.urls.map(PinnedApp.from)) }
    }
    private func addKeyword() {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        if !k.isEmpty { s.addPins([PinnedApp(name: k, exact: false, path: nil)]) }
        keyword = ""
    }
    private var recent: [String] { s.sums(s.visApps, .week).prefix(25).map(\.name).filter { !s.isPinned($0) } }

    var body: some View {
        Form {
            Section {
                if s.pins.isEmpty {
                    Text("No apps yet. Add one below, or drag apps here from Finder.").foregroundStyle(.secondary)
                }
                ForEach(s.pins) { p in
                    HStack(spacing: 10) {
                        Image(nsImage: s.pinIcon(p) ?? NSWorkspace.shared.icon(for: .unixExecutable)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name)
                            Text(p.exact ? (p.path ?? "Command-line tool") : "Any app whose name contains “\(p.name)”")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { s.removePin(p) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.borderless).help("Stop tracking").accessibilityLabel("Stop tracking \(p.name)")
                    }
                }
                HStack {
                    Button("Add App…") { choose() }
                    Menu("Add from Recent Activity") {
                        if recent.isEmpty { Text("No other apps used the network this week") }
                        ForEach(recent, id: \.self) { n in
                            Button { s.addPins([PinnedApp(name: n, exact: true, path: s.paths[n])]) } label: { Label { Text(n) } icon: { Image(nsImage: s.smallIcon(n)) } }
                        }
                    }
                    Spacer()
                }
            } header: { Text("Tracked apps") } footer: {
                Note("Each one gets its own line in the panel's Pinned section (and can go in the menu bar). Apps, helpers and background processes inside an app are counted together. Choose command-line tools, such as rclone, with Add App as well. You can also hover any app in the panel and click ☆.")
            }
            Section {
                HStack {
                    TextField("Name contains", text: $keyword, prompt: Text("For a process that isn't an app, e.g. “com.docker”")).labelsHidden().onSubmit(addKeyword)
                    Button("Add", action: addKeyword).disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: { Text("Add by name") } footer: { Note("Matches any app or process whose name contains the text.") }
            Section("Hidden apps") {
                if s.hiddenApps.isEmpty { Text("None. Right-click an app in the panel to hide it.").foregroundStyle(.secondary) }
                ForEach(s.hiddenApps.sorted(), id: \.self) { n in
                    LabeledContent(n) { Button("Show") { s.unhide(n, net: false) } }
                }
            }
        }
        .formStyle(.grouped)
        .dropDestination(for: URL.self) { urls, _ in s.addPins(urls.map(PinnedApp.from)); return !urls.isEmpty }
    }
}

struct AlertsPane: View {
    @AppStorage("thresholds") private var thresholds = "1,5,10,25,50,100"
    var body: some View {
        Form {
            Section {
                TextField("Notify at (GB)", text: $thresholds, prompt: Text("1, 5, 10, 25, 50, 100"))
            } header: { Text("Download alerts") } footer: { Note("A notification fires when a network's download this billing cycle passes each number of GB. Networks that have a limit also alert at 80% and 100% of it.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Data & about

struct DataPane: View {
    @ObservedObject var s: Store
    @State private var confirmReset = false
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    var body: some View {
        Form {
            Section("Export") {
                Button("Export Usage as CSV…") { s.exportCSV() }
            }
            Section {
                LabeledContent("Location") { Text(s.dataFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).foregroundStyle(.secondary).textSelection(.enabled) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([s.dataFolder]) }
            } header: { Text("Storage") } footer: { Note("Usage history is kept on this Mac for about 13 months and is never sent anywhere.") }
            Section {
                Button("Erase All Usage History…", role: .destructive) { confirmReset = true }
            }
            Section("About") {
                LabeledContent("Version") { Text("\(info["CFBundleShortVersionString"] as? String ?? "–") (\(info["CFBundleVersion"] as? String ?? "–"))") }
                Button("About NetMeter") { NSApp.orderFrontStandardAboutPanel(nil) }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Erase all usage history?", isPresented: $confirmReset) {
            Button("Erase", role: .destructive) { s.reset() }
        } message: { Text("This can't be undone. Your settings are kept.") }
    }
}
