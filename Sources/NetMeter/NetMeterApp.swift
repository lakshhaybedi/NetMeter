import SwiftUI

@main struct NetMeterApp: App {
    @StateObject var s = Store()

    init() { LegacyPreferences.migrate() }

    var body: some Scene {
        MenuBarExtra { Panel(s: s).defaultAppStorage(.app) } label: { BarLabel(s: s).defaultAppStorage(.app) }
            .menuBarExtraStyle(.window)

        Window("NetMeter", id: "main") { MainView(s: s).defaultAppStorage(.app) }
            .defaultSize(width: 1100, height: 740)
            .defaultLaunchBehavior(.suppressed)

        Settings { SettingsRoot(s: s).defaultAppStorage(.app) }

        .commands { AppCommands(s: s) }
    }
}

struct BarLabel: View {
    @ObservedObject var s: Store
    @AppStorage("items") private var items = "Used this month"
    @AppStorage("barNumbers") private var numbers = NumberStyle.compact
    @AppStorage("barStacked") private var stacked = false
    @AppStorage("onboarded") private var onboarded = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let text = s.barLines(items, numbers, stacked: false).joined()
        BarContent(s: s)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.isEmpty ? "NetMeter" : "NetMeter: \(text)")
            .task { if !onboarded { openWindow(id: "main") } }   // first launch: show the welcome screen
    }
}

struct AppCommands: Commands {
    @ObservedObject var s: Store
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Show Main Window") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut("0")
            Divider()
            Button("Export Usage as CSV…") { s.exportCSV() }.keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandMenu("Tracking") {
            Button(s.paused ? "Resume Tracking" : "Pause Tracking") { s.paused.toggle() }.keyboardShortcut("p", modifiers: [.command, .option])
            Divider()
            Picker("Traffic Shown", selection: $s.scope) { ForEach(Scope.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline)
        }
    }
}

/// Development builds used the placeholder id com.local.netmeter. Carry those preferences over once, without overwriting anything.
enum LegacyPreferences {
    static func migrate() {
        let d = UserDefaults.standard, old = "com.local.netmeter"
        guard !Store.demo, Bundle.main.bundleIdentifier != old, d.object(forKey: "migratedFromDevelopmentBuild") == nil else { return }
        d.set(true, forKey: "migratedFromDevelopmentBuild")
        for (k, v) in d.persistentDomain(forName: old) ?? [:] where d.object(forKey: k) == nil { d.set(v, forKey: k) }
    }
}
