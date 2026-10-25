import XCTest
@testable import Covio

final class HelperSignatureTests: XCTestCase {
    func testMainAppRequirementReadsTheInstalledRequirementFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-requirement-\(UUID().uuidString)")
        let requirement = "identifier \"com.wyz.covio\" and anchor apple generic"
        try requirement.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertEqual(
            HelperSignature.mainAppRequirement(requirementPath: file.path),
            requirement
        )
    }
}
