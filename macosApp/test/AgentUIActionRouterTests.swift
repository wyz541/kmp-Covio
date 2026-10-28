import XCTest
@testable import Covio

@MainActor
final class AgentUIActionRouterTests: XCTestCase {
    func testOpenPaneAcceptsOnlyTheFixedEnum() {
        let router = AgentUIActionRouter()
        var opened: AgentPane?
        router.install(
            openPane: { pane in
                opened = pane
                return true
            },
            readSetting: nil,
            changeSetting: nil
        )

        let result = router.openPane("files")
        let rejected = router.openPane("mars")

        XCTAssertTrue(result.ok)
        XCTAssertEqual(opened, .files)
        XCTAssertFalse(rejected.ok)
        XCTAssertEqual(rejected.errorCode, .invalidArguments)
    }

    func testReadSettingReturnsTypedAllowlistedValue() {
        let router = AgentUIActionRouter()
        router.install(
            openPane: nil,
            readSetting: { key in
                key == .batteryFloorPercent ? .integer(65) : nil
            },
            changeSetting: nil
        )

        let result = router.readSetting("power.batteryFloorPercent")
        let rejected = router.readSetting("system.anything")

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.data, .object([
            "key": .string("power.batteryFloorPercent"),
            "type": .string("integer"),
            "value": .int(65),
        ]))
        XCTAssertFalse(rejected.ok)
        XCTAssertEqual(rejected.errorCode, .invalidArguments)
    }

    func testSettingChangeParsesAndAppliesOneTypedValue() {
        let router = AgentUIActionRouter()
        var changes: [(AgentSettingKey, AgentSettingValue)] = []
        router.install(
            openPane: nil,
            readSetting: nil,
            changeSetting: { key, value in
                changes.append((key, value))
                return true
            }
        )

        let result = router.requestSettingChange("language", valueText: "zh-CN")
        let system = router.requestSettingChange("language", valueText: "system")
        let rejected = router.requestSettingChange("language", valueText: "mars")

        XCTAssertTrue(result.ok)
        XCTAssertTrue(system.ok)
        XCTAssertFalse(rejected.ok)
        XCTAssertEqual(rejected.errorCode, .invalidArguments)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes[0].0, .language)
        XCTAssertEqual(changes[0].1, .string("zh-CN"))
        XCTAssertEqual(changes[1].0, .language)
        XCTAssertEqual(changes[1].1, .string("system"))
    }
}
