import XCTest
@testable import NetMeter

final class ClassificationTests: XCTestCase {
    func testLANAddresses() {
        for a in ["192.168.0.5", "10.0.0.1", "172.16.4.2", "172.31.255.1", "169.254.1.1", "224.0.0.251", "255.255.255.255", "fe80::1", "fd12::1", "ff02::fb"] {
            XCTAssertTrue(Nettop.isLAN(a), a)
        }
    }
    func testInternetAddresses() {
        for a in ["17.253.1.1", "8.8.8.8", "172.32.0.1", "172.15.0.1", "100.64.1.1", "2606:4700::1111", "*", ""] {
            XCTAssertFalse(Nettop.isLAN(a), a)
        }
    }
    func testRemoteParsing() {
        XCTAssertEqual(Nettop.remote("tcp4 192.168.0.100:57609<->17.242.13.4:5223"), "17.242.13.4")
        XCTAssertEqual(Nettop.remote("udp6 2406:7400::1.58681<->2606:4700:4700::1111.443"), "2606:4700:4700::1111")
        XCTAssertEqual(Nettop.remote("udp4 *:5353<->*:*"), "*")
    }
}

final class BytesTests: XCTestCase {
    func testScopes() {
        let b = Bytes(i: 100, o: 50, li: 30, lo: 60)   // lo > o: must clamp, never underflow
        XCTAssertEqual(b.scoped(.all).i, 100)
        XCTAssertEqual(b.scoped(.internet).i, 70)
        XCTAssertEqual(b.scoped(.internet).o, 0)
        XCTAssertEqual(b.scoped(.local).i, 30)
        XCTAssertEqual(b.scoped(.local).o, 50)
    }
    func testDecodesOldDataWithoutLocalFields() throws {
        let b = try JSONDecoder().decode(Bytes.self, from: Data(#"{"i":5,"o":7}"#.utf8))
        XCTAssertEqual([b.i, b.o, b.li, b.lo], [5, 7, 0, 0])
    }
    func testRoundTrip() throws {
        let b = Bytes(i: 1, o: 2, li: 3, lo: 4)
        XCTAssertEqual(try JSONDecoder().decode(Bytes.self, from: JSONEncoder().encode(b)).lo, 4)
    }
}

final class BillingCycleTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 15))! }
    private func start(_ day: Int, _ now: Date) -> DateComponents { cal.dateComponents([.year, .month, .day], from: BillingCycle.start(day: day, now: now, calendar: cal)) }

    func testBeforeResetDayUsesPreviousMonth() {
        XCTAssertEqual(start(9, date(2026, 10, 5)), DateComponents(year: 2026, month: 9, day: 9))
    }
    func testOnAndAfterResetDay() {
        XCTAssertEqual(start(9, date(2026, 10, 9)), DateComponents(year: 2026, month: 10, day: 9))
        XCTAssertEqual(start(9, date(2026, 10, 30)), DateComponents(year: 2026, month: 10, day: 9))
    }
    func testWrapsAcrossYear() {
        XCTAssertEqual(start(9, date(2026, 1, 5)), DateComponents(year: 2025, month: 12, day: 9))
    }
    func testDefaultFirstOfMonthAndClamp() {
        XCTAssertEqual(start(1, date(2026, 10, 31)), DateComponents(year: 2026, month: 10, day: 1))
        XCTAssertEqual(start(31, date(2026, 3, 30)), DateComponents(year: 2026, month: 3, day: 28))   // days above 28 clamp to the 28th
        XCTAssertEqual(start(31, date(2026, 3, 20)), DateComponents(year: 2026, month: 2, day: 28))
    }
}

final class MenuBarFormatTests: XCTestCase {
    func testCompactAndTiny() {
        XCTAssertEqual(fmtBar(119_780_000_000, .compact), "120 GB")
        XCTAssertEqual(fmtBar(119_780_000_000, .tiny), "120G")
        XCTAssertEqual(fmtBar(1_234_000_000, .compact), "1.2 GB")
        XCTAssertEqual(fmtBar(12_300_000, .tiny), "12.3M")
        XCTAssertEqual(fmtBar(12_000_000, .tiny), "12M")        // trailing .0 dropped
        XCTAssertEqual(fmtBar(0, .tiny), "0B")
        XCTAssertEqual(fmtBar(999_960_000, .compact), "1 GB")   // rolls over instead of "1000 MB"
        XCTAssertEqual(fmtBar(99_960, .compact), "100 KB")
    }
    func testFullKeepsTheSystemFormat() {
        XCTAssertEqual(fmtBar(119_780_000_000, .full), fmt(119_780_000_000))
    }
}

final class PinnedAppTests: XCTestCase {
    func testFromFinderPick() {
        XCTAssertEqual(PinnedApp.from(URL(fileURLWithPath: "/Applications/Docker.app")).name, "Docker")
        XCTAssertEqual(PinnedApp.from(URL(fileURLWithPath: "/Applications/Docker.app")).path, "/Applications/Docker.app")
        // a helper inside a bundle counts as the outermost app, the same grouping the tracker uses
        XCTAssertEqual(PinnedApp.from(URL(fileURLWithPath: "/Applications/Docker.app/Contents/MacOS/Docker Desktop.app")).name, "Docker")
        let tool = PinnedApp.from(URL(fileURLWithPath: "/usr/local/bin/rclone"))
        XCTAssertEqual(tool.name, "rclone"); XCTAssertNil(tool.path)
    }
    func testMatching() {
        let exact = PinnedApp(name: "Plex", exact: true), loose = PinnedApp(name: "Plex", exact: false)
        XCTAssertTrue(exact.matches("plex")); XCTAssertFalse(exact.matches("Plex Media Server"))
        XCTAssertTrue(loose.matches("Plex Media Server")); XCTAssertFalse(loose.matches("Docker"))
    }
}
