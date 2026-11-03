@testable import CurrencyKit
import Foundation
import Testing

@MainActor
@Suite("Refresh scheduling")
struct SchedulerTests {
    /// Records each refresh the scheduler fires.
    @MainActor
    final class Recorder {
        var fires: [Set<RefreshTrigger>] = []

        func waitForFires(_ count: Int, timeout: Duration = .seconds(3)) async {
            let deadline = ContinuousClock.now + timeout
            while fires.count < count, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private func makeScheduler(_ recorder: Recorder, interval: Duration = .seconds(3_600), debounce: Duration = .milliseconds(80)) -> RefreshScheduler {
        RefreshScheduler(interval: interval, debounce: debounce) { triggers in
            recorder.fires.append(triggers)
        }
    }

    @Test func startFiresLaunchRefresh() async {
        let recorder = Recorder()
        let scheduler = makeScheduler(recorder)
        scheduler.start()
        await recorder.waitForFires(1)
        #expect(recorder.fires == [[.launch]])
        scheduler.stop()
    }

    @Test func burstOfTriggersIsDebouncedIntoOneRefresh() async {
        let recorder = Recorder()
        let scheduler = makeScheduler(recorder)
        scheduler.start()
        await recorder.waitForFires(1)

        scheduler.trigger(.wake)
        scheduler.trigger(.networkRestored)
        scheduler.trigger(.wake)
        await recorder.waitForFires(2)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(recorder.fires.count == 2)
        #expect(recorder.fires.last == [.wake, .networkRestored])
        scheduler.stop()
    }

    @Test func manualTriggerSkipsTheDebounce() async {
        let recorder = Recorder()
        let scheduler = makeScheduler(recorder, debounce: .seconds(10))
        scheduler.start()
        await recorder.waitForFires(1)
        scheduler.trigger(.manual)
        await recorder.waitForFires(2, timeout: .seconds(1))
        #expect(recorder.fires.last?.contains(.manual) == true)
        scheduler.stop()
    }

    @Test func intervalChangeAppliesImmediately() async {
        let recorder = Recorder()
        let scheduler = makeScheduler(recorder, interval: .seconds(3_600))
        scheduler.start()
        await recorder.waitForFires(1)

        // Without cancelling the hour-long sleep this would never fire.
        scheduler.setInterval(.milliseconds(100))
        await recorder.waitForFires(3)
        #expect(recorder.fires.count >= 3)
        #expect(recorder.fires.dropFirst().allSatisfy { $0 == [.timer] })
        scheduler.stop()
    }

    @Test func stopCancelsEverything() async {
        let recorder = Recorder()
        let scheduler = makeScheduler(recorder, interval: .milliseconds(50))
        scheduler.start()
        await recorder.waitForFires(1)
        scheduler.stop()
        let count = recorder.fires.count
        scheduler.trigger(.wake)
        try? await Task.sleep(for: .milliseconds(250))
        #expect(recorder.fires.count == count)
    }

    @Test func triggerForcing() {
        #expect(RefreshTrigger.manual.forcesRefresh)
        #expect(RefreshTrigger.wake.forcesRefresh)
        #expect(RefreshTrigger.networkRestored.forcesRefresh)
        #expect(!RefreshTrigger.timer.forcesRefresh)
        #expect(!RefreshTrigger.launch.forcesRefresh)
    }

    // MARK: - Reachability

    @Test func reachabilityOnlyFiresOnUnsatisfiedToSatisfiedEdge() {
        var tracker = ReachabilityTracker()
        #expect(tracker.update(satisfied: true) == false, "first observation only records")
        #expect(tracker.update(satisfied: true) == false)
        #expect(tracker.update(satisfied: false) == false)
        #expect(tracker.update(satisfied: false) == false)
        #expect(tracker.update(satisfied: true) == true)

        var startsOffline = ReachabilityTracker()
        #expect(startsOffline.update(satisfied: false) == false)
        #expect(startsOffline.update(satisfied: true) == true)
    }

    @Test func networkMonitorRecordsStateBeforeNotifying() {
        let monitor = NetworkMonitor()
        var seenWhileRestoring: Bool?
        var restoredCount = 0
        monitor.onRestored = {
            restoredCount += 1
            seenWhileRestoring = monitor.isOnline
        }
        monitor.handle(satisfied: false)
        #expect(monitor.isOnline == false)
        monitor.handle(satisfied: true)
        #expect(restoredCount == 1)
        #expect(seenWhileRestoring == true)
    }
}
