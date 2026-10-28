import XCTest
@testable import Covio

final class MultitouchContactSourceTests: XCTestCase {
    func testMissingFrameworkReturnsAStableFallbackResult() {
        let source = MultitouchContactSource(frameworkPath: "/missing/MultitouchSupport")
        let result = source.start { _ in }
        XCTAssertEqual(result, .frameworkMissing)
        XCTAssertEqual(result.errorCode, "multitouch_framework_missing")
        source.stop()
    }

    func testStartedResultHasNoErrorCode() {
        XCTAssertNil(MultitouchStartResult.started(deviceCount: 1).errorCode)
        XCTAssertEqual(
            MultitouchStartResult.symbolMissing.errorCode,
            "multitouch_symbol_missing"
        )
        XCTAssertEqual(MultitouchStartResult.noDevice.errorCode, "multitouch_no_device")
    }
}
