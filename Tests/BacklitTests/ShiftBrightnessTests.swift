import XCTest
import AppKit
@testable import Backlit

final class ShiftBrightnessTests: XCTestCase {
    private func event(key: UInt32 = 2, down: Bool = true, repeat repeated: Bool = false,
                       flags: NSEvent.ModifierFlags = .shift) -> ShiftBrightnessEvent? {
        ShiftBrightnessEvent.decode(type:NSEvent.EventType.systemDefined.rawValue,subtype:8,
            data1:Int((key << 16) | ((down ? 0x0a : 0x0b) << 8) | (repeated ? 1 : 0)),modifiers:flags)
    }
    func testOnlyAuxiliaryBrightnessPayloadsAreRecognized() {
        XCTAssertEqual(event()?.action,.increase); XCTAssertEqual(event(key:3)?.action,.decrease)
        for key: UInt32 in [0,1,7,16,21,22,65535] { XCTAssertNil(event(key:key)) }
        XCTAssertNil(ShiftBrightnessEvent.decode(type:NSEvent.EventType.keyDown.rawValue,subtype:8,data1:2 << 16,modifiers:.shift))
        XCTAssertNil(ShiftBrightnessEvent.decode(type:14,subtype:1,data1:2 << 16,modifiers:.shift))
        XCTAssertNil(ShiftBrightnessEvent.decode(type:14,subtype:8,data1:(2 << 16) | (0x0c << 8),modifiers:.shift))
    }
    func testUnmodifiedAndEveryAdditionalModifierRemainNative() {
        for flags: NSEvent.ModifierFlags in [[],.option,.command,.control,[.shift,.option],[.shift,.command],[.shift,.control],[.shift,.function]] {
            var policy = ShiftBrightnessPolicy()
            XCTAssertEqual(policy.handle(event(flags:flags),at:1),.pass)
            XCTAssertEqual(policy.handle(event(down:false,flags:flags),at:2),.pass)
        }
    }
    func testShiftOnlyPairsDownAndUpWithoutTwoBrightnessActions() {
        var policy = ShiftBrightnessPolicy()
        XCTAssertEqual(policy.handle(event(),at:1),.init(consume:true,action:.increase))
        XCTAssertEqual(policy.handle(event(down:false),at:2),.init(consume:true,action:nil))
        XCTAssertEqual(policy.handle(event(down:false),at:3),.pass)
    }
    func testCapsLockDoesNotTurnShiftIntoADifferentShortcut() {
        var policy = ShiftBrightnessPolicy()
        XCTAssertEqual(policy.handle(event(flags:[.shift,.capsLock]),at:1),.init(consume:true,action:.increase))
    }
    func testReleasingShiftFirstDoesNotLeakOwnedRepeatsOrKeyUp() {
        var policy = ShiftBrightnessPolicy(); _ = policy.handle(event(),at:1)
        XCTAssertEqual(policy.handle(event(repeat:true,flags:[]),at:2),.init(consume:true,action:nil))
        XCTAssertEqual(policy.handle(event(down:false,flags:[]),at:3),.init(consume:true,action:nil))
        XCTAssertEqual(policy.handle(event(flags:[]),at:4),.pass)
    }
    func testAddingShiftDuringANativeHoldDoesNotHijackTheGesture() {
        var policy = ShiftBrightnessPolicy()
        XCTAssertEqual(policy.handle(event(flags:[]),at:1),.pass)
        XCTAssertEqual(policy.handle(event(repeat:true),at:2),.pass)
        XCTAssertEqual(policy.handle(event(down:false),at:3),.pass)
        XCTAssertEqual(policy.handle(event(),at:4),.init(consume:true,action:.increase))
    }
    func testEnablingDuringARepeatDoesNotCaptureAnUnknownInitialPress() {
        var policy = ShiftBrightnessPolicy()
        XCTAssertEqual(policy.handle(event(repeat:true),at:1),.pass)
        XCTAssertEqual(policy.handle(event(down:false),at:2),.pass)
    }
    func testRepeatRateAndInvalidClocksCannotFloodBrightnessChanges() {
        var policy = ShiftBrightnessPolicy(); _ = policy.handle(event(),at:100)
        XCTAssertEqual(policy.handle(event(repeat:true),at:100.01),.init(consume:true,action:nil))
        XCTAssertEqual(policy.handle(event(repeat:true),at:100.09),.init(consume:true,action:.increase))
        XCTAssertEqual(policy.handle(event(repeat:true),at:99),.init(consume:true,action:nil))
        XCTAssertEqual(policy.handle(event(repeat:true),at:.nan),.init(consume:true,action:nil))
        XCTAssertEqual(policy.handle(event(repeat:true),at:.infinity),.init(consume:true,action:nil))
    }
    func testChangingModifiersDuringAnOwnedHoldDoesNotTriggerAnotherTarget() {
        var policy = ShiftBrightnessPolicy(); _ = policy.handle(event(),at:1)
        XCTAssertEqual(policy.handle(event(repeat:true,flags:[.shift,.option]),at:2),.init(consume:true,action:nil))
        XCTAssertEqual(policy.handle(event(down:false,flags:[.shift,.option]),at:3),.init(consume:true,action:nil))
        XCTAssertEqual(policy.handle(event(flags:[.shift,.option]),at:4),.pass)
    }
    func testUnrelatedEventsAndOtherBrightnessDirectionPassIndependently() {
        var policy = ShiftBrightnessPolicy(); _ = policy.handle(event(),at:1)
        XCTAssertEqual(policy.handle(nil,at:2),.pass)
        XCTAssertEqual(policy.handle(event(key:3,flags:[]),at:3),.pass)
        XCTAssertEqual(policy.handle(event(down:false,flags:[]),at:4),.init(consume:true,action:nil))
        XCTAssertEqual(policy.handle(event(key:3,down:false,flags:[]),at:5),.pass)
    }
    func testResetAfterDisableCannotRetainOrReplayAPress() {
        var policy = ShiftBrightnessPolicy(); _ = policy.handle(event(),at:1)
        policy.reset()
        XCTAssertEqual(policy.handle(event(down:false),at:2),.pass)
        XCTAssertEqual(policy.handle(event(repeat:true),at:3),.pass)
    }
    @MainActor func testPermissionDeniedNeverStartsATapAndOnlyExplicitActionsMayPrompt() {
        var requests: [Bool] = []
        let filter = ShiftBrightnessKeys(accessibility:{requests.append($0);return false})
        XCTAssertNotNil(filter.start(prompt:false)); XCTAssertFalse(filter.running)
        XCTAssertNotNil(filter.start(prompt:true)); XCTAssertFalse(filter.running)
        XCTAssertEqual(requests,[false,true])
        filter.stop(); filter.stop(); XCTAssertFalse(filter.running)
    }
    @MainActor func testListeningPermissionIsPreflightedBeforeAnyTapCanBeCreated() {
        var checks = 0
        let filter = ShiftBrightnessKeys(accessibility:{_ in true},listeningAccess:{checks += 1;return false})
        XCTAssertTrue(filter.start(prompt:false)?.contains("Input Monitoring") == true)
        XCTAssertEqual(checks,1); XCTAssertFalse(filter.running)
    }
}
