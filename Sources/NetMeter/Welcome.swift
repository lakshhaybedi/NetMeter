import SwiftUI
import ServiceManagement

/// First-run sheet: what the app is, and the two permissions it benefits from, explained before macOS asks.
struct WelcomeView: View {
    @ObservedObject var s: Store
    var done: () -> Void
    @State private var login = SMAppService.mainApp.status == .enabled

    private func step<Accessory: View>(_ symbol: String, _ title: String, _ detail: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                accessory()
            }
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage).resizable().frame(width: 72, height: 72).accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Welcome to NetMeter").font(.largeTitle.bold())
                Text("See what your Mac is using, by network and by app, right from the menu bar.").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                step("menubar.rectangle", "It lives in your menu bar",
                     "Click the ⇅ item for live traffic and this billing cycle's usage. Right-click a network to set its monthly limit and reset day.")
                step("wifi", "Know which network you're on",
                     "Allow Location so macOS tells NetMeter the Wi-Fi network's name. Nothing leaves your Mac.") {
                    if s.locationAllowed { Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout) }
                    else { Button("Allow Location…") { s.requestLocation() } }
                }
                step("bell", "Get warned before you hit your cap",
                     "Notifications tell you as usage approaches your limit.") {
                    if s.notifStatus == .authorized { Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout) }
                    else { Button("Allow Notifications…") { s.requestNotifications() } }
                }
                step("power", "Start with your Mac", "So usage is counted from the moment you log in.") {
                    Toggle("Open NetMeter at login", isOn: $login)
                        .onChange(of: login) { _, on in
                            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                            catch { login = SMAppService.mainApp.status == .enabled }
                        }
                }
            }
            Button("Get Started", action: done).buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(32).frame(width: 540)
    }
}
