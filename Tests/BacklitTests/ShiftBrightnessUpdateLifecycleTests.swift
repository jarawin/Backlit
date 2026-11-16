import XCTest
@testable import Backlit

/// Exercise the real update/quit lifecycle using a synthetic key filter only.
/// No event tap, permission request, power monitor, or hardware write is used.
@MainActor final class ShiftBrightnessUpdateLifecycleTests: XCTestCase {
    private final class Filter {
        var running = false
        var prompts: [Bool] = []
        var failure: String?
        var stops = 0
        func start(_ prompt: Bool) -> String? {
            prompts.append(prompt)
            if let failure { return failure }
            running = true
            return nil
        }
        func stop() { running = false; stops += 1 }
    }

    private func fixture(_ body: (AppModel, UserDefaults, Filter) -> Void) {
        let suite = "local.backlit.shift-brightness-update." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let filter = Filter()
        let model = AppModel(demo: true, defaults: defaults)
        model.shiftBrightnessDriver = .init(start: filter.start, stop: filter.stop)
        defer {
            XCTAssertTrue(model.prepareQuit())
            defaults.removePersistentDomain(forName: suite)
        }
        body(model, defaults, filter)
        XCTAssertFalse(model.shiftBrightnessKeys.running, "The native filter must remain untouched")
    }

    func testFailedUpdateRestartsPreviouslyEnabledFilterWithoutPrompting() {
        fixture { model, defaults, filter in
            model.configureShiftBrightness(true, prompt: true)
            XCTAssertTrue(filter.running)
            XCTAssertTrue(model.prepareQuit())
            XCTAssertFalse(filter.running)
            XCTAssertTrue(defaults.bool(forKey: "shortcut.shiftBrightness.enabled"))

            model.resumeAfterUpdateFailure()

            XCTAssertEqual(filter.prompts, [true, false])
            XCTAssertTrue(filter.running)
            XCTAssertTrue(model.shiftBrightnessEnabled)
            XCTAssertTrue(defaults.bool(forKey: "shortcut.shiftBrightness.enabled"))
            XCTAssertTrue(model.lifecycleAllowsFrames)
            model.resumeAfterUpdateFailure()
            XCTAssertEqual(filter.prompts, [true, false], "Repeated failure callbacks cannot restart twice")
        }
    }

    func testBlockedRestartLeavesFilterOffAndReportsTheFailureWithoutPrompting() {
        fixture { model, defaults, filter in
            model.configureShiftBrightness(true, prompt: true)
            XCTAssertTrue(model.prepareQuit())
            filter.failure = "Fixture permission is no longer available"

            model.resumeAfterUpdateFailure()

            XCTAssertEqual(filter.prompts, [true, false])
            XCTAssertFalse(filter.running)
            XCTAssertFalse(model.shiftBrightnessEnabled)
            XCTAssertFalse(defaults.bool(forKey: "shortcut.shiftBrightness.enabled"))
            XCTAssertEqual(model.shiftBrightnessStatus, filter.failure)
            XCTAssertEqual(model.notice, filter.failure)
            model.resumeAfterUpdateFailure()
            XCTAssertEqual(filter.prompts, [true, false])
        }
    }

    func testFailedUpdateDoesNotOptIntoADisabledFilter() {
        fixture { model, defaults, filter in
            defaults.set(false, forKey: "shortcut.shiftBrightness.enabled")
            XCTAssertTrue(model.prepareQuit())

            model.resumeAfterUpdateFailure()

            XCTAssertTrue(filter.prompts.isEmpty)
            XCTAssertFalse(filter.running)
            XCTAssertFalse(model.shiftBrightnessEnabled)
            XCTAssertFalse(defaults.bool(forKey: "shortcut.shiftBrightness.enabled"))
        }
    }
}
