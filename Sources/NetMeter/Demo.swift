import SwiftUI
import CoreLocation
import UserNotifications

/// `NetMeter --demo` shows synthetic, in-memory data (for screenshots and review). It never reads or writes the real
/// history or preferences, and starts no timers or `nettop` polling.
extension Store {
    static let demo = CommandLine.arguments.contains("--demo")

    func loadDemo() {
        struct LCG: RandomNumberGenerator {
            var s: UInt64
            mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
        }
        var g = LCG(s: 7)
        func r(_ lo: Double, _ hi: Double) -> Double { Double.random(in: lo...hi, using: &g) }
        let cal = Calendar.current
        let pool: [(name: String, id: String, share: Double, local: Double)] = [
            ("Safari", "com.apple.Safari", 0.30, 0), ("TV", "com.apple.TV", 0.16, 0.04), ("Music", "com.apple.Music", 0.14, 0.03),
            ("Photos", "com.apple.Photos", 0.12, 0), ("App Store", "com.apple.AppStore", 0.07, 0), ("Podcasts", "com.apple.podcasts", 0.05, 0),
            ("Mail", "com.apple.mail", 0.04, 0), ("Messages", "com.apple.MobileSMS", 0.03, 0), ("Maps", "com.apple.Maps", 0.02, 0),
        ]
        for a in pool { paths[a.name] = NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.id)?.path }

        for back in 0..<45 {
            let date = cal.date(byAdding: .day, value: -back, to: Date())!, key = Self.dayFmt.string(from: date)
            let wk = cal.isDateInWeekend(date) ? 1.5 : 1.0
            let home = r(5e9, 15e9) * wk * (back == 0 ? 0.45 : 1)
            var n: [String: Bytes] = ["Home Wi-Fi": Bytes(i: UInt64(home), o: UInt64(home * 0.07), li: UInt64(home * 0.05), lo: UInt64(home * 0.01))]
            var spot = 0.0
            if back % 4 == 1 { spot = r(0.4e9, 3.2e9); n["Phone Hotspot"] = Bytes(i: UInt64(spot), o: UInt64(spot * 0.09)) }
            nets[key] = n
            var a: [String: Bytes] = [:]
            for app in pool {
                let part = (home + spot) * app.share * r(0.6, 1.4)
                a[app.name] = Bytes(i: UInt64(part), o: UInt64(part * 0.06), li: UInt64(part * app.local), lo: UInt64(part * app.local * 0.2))
            }
            for sys in ["mDNSResponder", "apsd", "cloudd"] { a[sys] = Bytes(i: UInt64(r(2e6, 40e6)), o: UInt64(r(1e6, 20e6))) }
            apps[key] = a
        }
        budgets = ["Home Wi-Fi": 1200, "Phone Hotspot": 100]
        cycleDays = ["Phone Hotspot": 9]
        symbols = ["Phone Hotspot": "personalhotspot"]
        baselines[baselineKey("Home Wi-Fi")] = Int64(210e9)       // usage before NetMeter started counting this cycle
        baselines[baselineKey("Phone Hotspot")] = Int64(66e9)
        pins = [PinnedApp(name: "Music", exact: true, path: paths["Music"]), PinnedApp(name: "TV", exact: true, path: paths["TV"])]
        network = "Home Wi-Fi"
        downHist = (0..<60).map { i in max(0, 2.2e6 + 1.8e6 * sin(Double(i) / 4) + r(0, 1.2e6) + (i > 50 ? 2.5e6 : 0)) }
        upHist = (0..<60).map { i in max(0, 0.18e6 + 0.1e6 * sin(Double(i) / 5) + r(0, 0.12e6)) }
        down = downHist.last!; up = upHist.last!
        locationStatus = .authorizedAlways; notifStatus = .authorized
    }
}
