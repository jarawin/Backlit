import XCTest
@testable import Backlit

final class ExternalControlTests: XCTestCase {
    static var ready: ExternalControlContext {
        .init(hardwareAvailable:true,controlWanted:true,controlling:true,availableModes:GlowMode.allCases)
    }
    private func rejects(_ context: ExternalControlContext, _ command: LightCommand, _ code: ExternalControlError.Code,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try context.validate(command),file:file,line:line) {
            XCTAssertEqual(($0 as? ExternalControlError)?.code,code,file:file,line:line)
        }
    }
    func testTurningOnAnAlreadySelectedMusicModeRequiresPreviousLocalAuthorization() {
        var context = Self.ready; context.mode = .music; context.enabled = false
        rejects(context,LightCommand(enabled:true),.permissionRequired)
        rejects(context,LightCommand(mode:.music),.permissionRequired)
        XCTAssertNoThrow(try context.validate(LightCommand(enabled:false)))
        context.musicAuthorized = true
        XCTAssertNoThrow(try context.validate(LightCommand(enabled:true)))
    }
    func testTypingNeverRequestsItsOwnPermissionThroughExternalControls() {
        var context = Self.ready; context.mode = .typing; context.enabled = false
        rejects(context,LightCommand(enabled:true),.permissionRequired)
        rejects(context,LightCommand(mode:.typing),.permissionRequired)
        context.typingAuthorized = true
        XCTAssertNoThrow(try context.validate(LightCommand(mode:.typing)))
    }
    func testBatteryBrightnessIsExplicitlyAutomaticAndManualModeCanBeSelectedInOneValidatedRequest() {
        var context = Self.ready; context.mode = .battery
        rejects(context,LightCommand(brightness:0.4),.brightnessAutomatic)
        rejects(context,LightCommand(brightness:0.4,mode:.battery),.brightnessAutomatic)
        XCTAssertNoThrow(try context.validate(LightCommand(brightness:0.4,mode:.steady)))
    }
    func testUnsafeLifecycleStatesRejectMutationsButAnOwnedPausedLightCanBeTurnedOff() {
        var context = Self.ready; context.paused = "Display asleep"; context.controlling = false
        rejects(context,LightCommand(enabled:true),.paused)
        XCTAssertNoThrow(try context.validate(LightCommand(enabled:false)))
        context.busy = true
        rejects(context,LightCommand(enabled:false),.busy)
        context.needsRecovery = true
        rejects(context,LightCommand(enabled:false),.recoveryRequired)
        context = Self.ready; context.controlWanted = false
        rejects(context,LightCommand(enabled:false),.hardwareUnavailable)
    }
    func testUnsupportedModesUnknownSettingsAndNonfiniteBrightnessAreRejected() {
        var context = Self.ready; context.availableModes = [.steady]
        rejects(context,LightCommand(mode:.touch),.invalidArgument)
        rejects(context,LightCommand(),.invalidArgument)
        for value in [Double.nan,Double.infinity,-0.1,1.1] {
            rejects(context,LightCommand(brightness:value),.invalidArgument)
        }
    }
    func testAgentRateLimitIsBoundedAcrossBurstsAndClockRegression() {
        var limiter = ExternalControlRateLimit()
        for _ in 0..<4 { XCTAssertTrue(limiter.admit(at:100)) }
        XCTAssertFalse(limiter.admit(at:100))
        XCTAssertFalse(limiter.admit(at:99))
        XCTAssertFalse(limiter.admit(at:.infinity))
        XCTAssertTrue(limiter.admit(at:100.5))
        XCTAssertFalse(limiter.admit(at:100.5))
    }
    func testAnOwnedRecoveryJournalDoesNotMakeHealthyExternalControlsUnavailable() {
        XCTAssertFalse(ExternalControlContext.recoveryRequired(controlling:true,journalPresent:true,failurePresent:false))
        XCTAssertTrue(ExternalControlContext.recoveryRequired(controlling:false,journalPresent:true,failurePresent:false))
        XCTAssertTrue(ExternalControlContext.recoveryRequired(controlling:true,journalPresent:true,failurePresent:true))
    }
    @MainActor func testProductionAutomationEntryDoesNotChangePreferencesOnRejectedTarget() throws {
        let suite = "local.backlit.external." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set("music",forKey:"mode"); defaults.set(false,forKey:"enabled")
        let model = AppModel(demo:true,defaults:defaults,externalControlObservation:{Self.ready})
        model.automationsEnabled = true
        XCTAssertThrowsError(try model.performAutomation(.power(true))) {
            XCTAssertEqual(($0 as? ExternalControlError)?.code,.permissionRequired)
        }
        XCTAssertFalse(model.enabled); XCTAssertFalse(defaults.bool(forKey:"enabled"))
        XCTAssertEqual(model.mode,.music)
    }
    @MainActor func testProductionAutomationUsesSharedValidationAndAppliesValidChanges() throws {
        let suite = "local.backlit.external." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set("battery",forKey:"mode")
        let model = AppModel(demo:true,defaults:defaults,externalControlObservation:{Self.ready})
        model.automationsEnabled = true
        try model.performAutomation(.brightness(0.42))
        XCTAssertEqual(model.brightness,0.42,"Legacy controls preserve the saved manual slider")
        XCTAssertNotEqual(model.agentLightState().calculatedOutputPercent,42,"Battery output remains automatic")
        try model.performAutomation(.mode(.steady))
        try model.performAutomation(.brightness(0.42))
        XCTAssertEqual(defaults.double(forKey:"brightness"),0.42)
        model.automationsEnabled = false
        XCTAssertThrowsError(try model.performAutomation(.power(false)))
        XCTAssertTrue(model.enabled)
    }
    @MainActor func testPreviewStatusSeparatesManualBrightnessCalculatedOutputAndUnknownHardware() {
        let suite = "local.backlit.external." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let model = AppModel(demo:true,defaults:defaults)
        model.mode = .battery; model.brightness = 0.13; model.tick()
        let state = model.agentLightState()
        XCTAssertEqual(state.manualBrightnessPercent,13,accuracy:0.001)
        XCTAssertNotEqual(state.calculatedOutputPercent,13)
        XCTAssertNil(state.hardwareEnabled); XCTAssertTrue(state.preview)
        XCTAssertFalse(state.hardwareSupported)
        XCTAssertEqual(state.applicationResult,"unavailable")
        XCTAssertEqual(state.access,.off)
        XCTAssertEqual(state.availableModes.first(where:{$0.name == "music"})?.selectable,false)
    }
    func testClientSetupContainsNoKeyOrProjectConfigurationMutation() {
        XCTAssertEqual(MCPSetup.command(claude:false),"codex mcp add backlit -- /Applications/Backlit.app/Contents/MacOS/Backlit --mcp")
        XCTAssertTrue(MCPSetup.command(claude:true).contains("--scope user"))
        XCTAssertFalse(MCPSetup.command(claude:true).contains("--env"))
    }
}
