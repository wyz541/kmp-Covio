import XCTest
@testable import Covio

final class StatsFanControlTests: XCTestCase {
    func testModeThreeNormalizesToAutomatic() {
        XCTAssertEqual(
            StatsFanModeResolver.normalizedMode(
                rawValue: 3,
                appleSilicon: true,
                fanIndex: 0,
                fansModeBits: nil
            ),
            .automatic
        )
        XCTAssertTrue(StatsFanMode.auto3.isAutomatic)
    }

    func testModeKeyFollowsStatsLowerCaseProbe() {
        XCTAssertEqual(
            StatsFanModeResolver.modeKey(
                for: 1,
                availableKeys: ["F0md", "F1md", "F1Md"],
                appleSilicon: true
            ),
            "F1md"
        )
        XCTAssertEqual(
            StatsFanModeResolver.modeKey(
                for: 1,
                availableKeys: ["F1Md"],
                appleSilicon: true
            ),
            "F1Md"
        )
    }

    func testAutomaticModeWritesZeroModeAndTarget() throws {
        let fake = FakeStatsFanSMC(
            values: [
                "F0Md": Data([1]),
                "F0Tg": SMCValue.floatBytes(2_400),
            ],
            types: [
                "F0Md": "ui8 ",
                "F0Tg": "flt ",
            ]
        )
        let control = StatsFanControl(
            access: fake,
            allKeys: fake.keys,
            appleSilicon: true
        )

        try control.setMode(0, mode: .automatic)

        XCTAssertEqual(fake.values["F0Md"], Data([0]))
        XCTAssertEqual(fake.values["F0Tg"], Data(repeating: 0, count: 4))
    }

    func testForcedModeUsesStatsUnlockPath() throws {
        let fake = FakeStatsFanSMC(
            values: ["F0Md": Data([0])],
            types: ["F0Md": "ui8 "]
        )
        let control = StatsFanControl(
            access: fake,
            allKeys: fake.keys,
            appleSilicon: true
        )

        try control.hold(0)

        XCTAssertEqual(fake.values["F0Md"], Data([1]))
        XCTAssertEqual(control.holdingCount, 1)
        XCTAssertTrue(control.isHolding(0))
    }

    func testEnsureHeldReclaimsModeAfterSystemReset() throws {
        let fake = FakeStatsFanSMC(
            values: ["F0Md": Data([0])],
            types: ["F0Md": "ui8 "]
        )
        let control = StatsFanControl(
            access: fake,
            allKeys: fake.keys,
            appleSilicon: true
        )
        try control.hold(0)
        fake.values["F0Md"] = Data([0])

        try control.ensureHeld(0)

        XCTAssertEqual(fake.values["F0Md"], Data([1]))
    }

    func testFanSpeedUsesTargetTypeAndStatsMaximum() throws {
        let fake = FakeStatsFanSMC(
            values: [
                "F0Md": Data([1]),
                "F0Mx": SMCValue.fpe2Bytes(6_000),
                "F0Tg": Data(repeating: 0, count: 4),
            ],
            types: [
                "F0Md": "ui8 ",
                "F0Mx": "fpe2",
                "F0Tg": "flt ",
            ]
        )
        let control = StatsFanControl(
            access: fake,
            allKeys: fake.keys,
            appleSilicon: true
        )

        try control.setFanSpeed(0, speed: 7_000)

        XCTAssertEqual(fake.values["F0Tg"], SMCValue.floatBytes(6_000))
    }

    func testFpe2TargetClearsTrailingStatsBytes() throws {
        let fake = FakeStatsFanSMC(
            values: [
                "F0Md": Data([1]),
                "F0Tg": Data([0xAA, 0xBB, 0xCC, 0xDD]),
            ],
            types: [
                "F0Md": "ui8 ",
                "F0Tg": "fpe2",
            ]
        )
        let control = StatsFanControl(
            access: fake,
            allKeys: fake.keys,
            appleSilicon: true
        )

        try control.setFanSpeed(0, speed: 2_000)

        let expected = SMCValue.fpe2Bytes(2_000) + Data([0, 0])
        XCTAssertEqual(fake.values["F0Tg"], expected)
    }

    func testIntelModeUpdatesFsMask() throws {
        let fake = FakeStatsFanSMC(
            values: [
                "F1Md": Data([0]),
                "FS! ": Data([0, 0]),
            ],
            types: [
                "F1Md": "ui8 ",
                "FS! ": "ui16",
            ]
        )
        let control = StatsFanControl(
            access: fake,
            allKeys: fake.keys,
            appleSilicon: false
        )

        try control.setMode(1, mode: .forced)
        XCTAssertEqual(fake.values["F1Md"], Data([1]))
        XCTAssertEqual(fake.values["FS! "], Data([0, 2]))

        try control.setMode(1, mode: .automatic)
        XCTAssertEqual(fake.values["FS! "], Data([0, 0]))
    }

    func testResetWritesFtstZero() throws {
        let fake = FakeStatsFanSMC(
            values: [
                "Ftst": Data([1]),
                "FNum": Data([1]),
                "F0Md": Data([1]),
            ],
            types: [
                "Ftst": "ui8 ",
                "FNum": "ui8 ",
                "F0Md": "ui8 ",
            ]
        )
        let control = StatsFanControl(
            access: fake,
            allKeys: fake.keys,
            appleSilicon: true
        )

        try control.resetFanControl()

        XCTAssertEqual(fake.values["Ftst"], Data([0]))
    }

    func testFailedReleaseKeepsFanMarkedAsHeld() throws {
        let fake = FakeStatsFanSMC(
            values: [
                "F0Md": Data([0]),
                "F0Tg": Data(repeating: 0, count: 4),
                "Ftst": Data([1]),
            ],
            types: [
                "F0Md": "ui8 ",
                "F0Tg": "flt ",
                "Ftst": "ui8 ",
            ]
        )
        let control = StatsFanControl(
            access: fake,
            allKeys: fake.keys,
            appleSilicon: true
        )
        try control.hold(0)
        fake.failingWrites = ["F0Md", "Ftst"]

        XCTAssertThrowsError(try control.releaseAll())
        XCTAssertTrue(control.isHolding(0))
    }
}

private final class FakeStatsFanSMC: StatsFanSMC {
    var values: [String: Data]
    let types: [String: String]
    var failingWrites: Set<String> = []

    var keys: [SMCAccessKey] {
        values.keys.compactMap(SMCAccessKey.init).sorted { $0.description < $1.description }
    }

    init(values: [String: Data], types: [String: String]) {
        self.values = values
        self.types = types
    }

    func keyInfo(_ key: SMCAccessKey) throws -> SMCAccessKeyInfo {
        guard let type = types[key.description],
              let typeKey = SMCAccessKey(type),
              let data = values[key.description]
        else { throw SMCAccessError.keyNotFound(key.description) }
        return SMCAccessKeyInfo(dataSize: UInt32(data.count), dataType: typeKey.raw)
    }

    func read(_ key: SMCAccessKey) throws -> Data {
        guard let value = values[key.description] else {
            throw SMCAccessError.keyNotFound(key.description)
        }
        return value
    }

    func write(_ key: SMCAccessKey, data: Data) throws {
        if failingWrites.contains(key.description) {
            throw SMCAccessError.callFailed(0xE00002BC)
        }
        guard values[key.description] != nil else {
            throw SMCAccessError.keyNotFound(key.description)
        }
        values[key.description] = data
    }
}
