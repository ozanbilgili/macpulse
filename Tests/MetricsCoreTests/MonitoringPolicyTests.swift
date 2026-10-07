import XCTest
@testable import MetricsCore

final class MonitoringPolicyTests: XCTestCase {
    func testDefaultIntervalsRespectCounterGap() {
        let p = MonitorPreferences()
        XCTAssertEqual(p.pollingInterval(visible: true), 2)
        XCTAssertEqual(p.pollingInterval(visible: false), 10)
        for interval in MonitorPreferences.intervals {
            let custom = MonitorPreferences(interval: interval)
            XCTAssertLessThanOrEqual(custom.backgroundInterval, 20)
            XCTAssertGreaterThanOrEqual(custom.backgroundInterval, interval)
        }
    }
    func testInvalidIntervalRestoresSafeDefault() {
        for invalid in [-1, 0, 1, 3, 20, 100] { XCTAssertEqual(MonitorPreferences(interval: invalid).interval, 2) }
    }
    func testMenuMetricsHaveStableOrderNoDuplicatesAndBoundedWidth() {
        XCTAssertEqual(MonitorPreferences(menuMetrics: [.battery, .cpu, .cpu, .disk, .memory]).menuMetrics, [.cpu, .memory, .disk])
    }
    func testIconOnlyPreferenceSurvivesRoundTrip() throws {
        let p = MonitorPreferences(theme: .light, interval: 5, menuMetrics: [])
        XCTAssertEqual(try JSONDecoder().decode(MonitorPreferences.self, from: JSONEncoder().encode(p)), p)
    }
    func testUnknownStoredValuesAreBounded() throws {
        let data = Data(#"{"theme":"future","interval":0,"menuMetrics":["future","battery","cpu","cpu"]}"#.utf8)
        let p = try JSONDecoder().decode(MonitorPreferences.self, from: data)
        XCTAssertEqual(p.theme, .dark); XCTAssertEqual(p.interval, 2); XCTAssertEqual(p.menuMetrics, [.cpu, .battery])
    }
    func testMissingKeysRestoreDefaults() throws {
        XCTAssertEqual(try JSONDecoder().decode(MonitorPreferences.self, from: Data("{}".utf8)), MonitorPreferences())
    }
    func testFirstReadRequiresBaseline() {
        var l = SamplingLifecycle(); XCTAssertTrue(l.resetRequired)
        l.didReset(for: l.generation); XCTAssertFalse(l.resetRequired)
    }
    func testPauseRejectsInflightReadEvenAfterImmediateResume() {
        var l = SamplingLifecycle(); let token = l.generation
        l.setPaused(true); l.setPaused(false)
        XCTAssertTrue(l.canSample); XCTAssertFalse(l.accepts(token)); XCTAssertTrue(l.resetRequired)
    }
    func testSleepWakeRejectsReadAndRequiresNewBaseline() {
        var l = SamplingLifecycle(); l.didReset(for: l.generation); let token = l.generation
        l.setSleeping(true); XCTAssertFalse(l.canSample)
        l.setSleeping(false); XCTAssertFalse(l.accepts(token)); XCTAssertTrue(l.resetRequired)
    }
    func testWakePreservesManualPause() {
        var l = SamplingLifecycle(); l.setPaused(true); l.setSleeping(true); l.setSleeping(false)
        XCTAssertTrue(l.paused); XCTAssertFalse(l.canSample)
        l.setPaused(false); XCTAssertTrue(l.canSample)
    }
    func testPauseResumeDuringSleepDoesNotStartSampling() {
        var l = SamplingLifecycle(); l.setSleeping(true); l.setPaused(true); l.setPaused(false)
        XCTAssertFalse(l.canSample); l.setSleeping(false); XCTAssertTrue(l.canSample)
    }
    func testOldResetCannotAcknowledgeNewGeneration() {
        var l = SamplingLifecycle(); let token = l.generation; l.setSleeping(true); l.setSleeping(false)
        l.didReset(for: token); XCTAssertTrue(l.resetRequired)
        l.didReset(for: l.generation); XCTAssertFalse(l.resetRequired)
    }
    func testRepeatedNotificationsAreIdempotent() {
        var l = SamplingLifecycle(); XCTAssertTrue(l.setSleeping(true)); let generation = l.generation
        XCTAssertFalse(l.setSleeping(true)); XCTAssertEqual(l.generation, generation)
        XCTAssertTrue(l.setPaused(true)); let pausedGeneration = l.generation
        XCTAssertFalse(l.setPaused(true)); XCTAssertEqual(l.generation, pausedGeneration)
    }
    func testShutdownPermanentlyRejectsReads() {
        var l = SamplingLifecycle(); let token = l.generation; l.stop(); l.setSleeping(false); l.setPaused(false)
        XCTAssertFalse(l.canSample); XCTAssertFalse(l.accepts(token))
    }
}
