import Foundation
import XCTest
@testable import Covio

@MainActor
final class ModelSetupPresentationTests: XCTestCase {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testDownloadingStateCarriesTextAndProgressForVoiceOver() {
        let state = makeState(phase: .downloading, fraction: 0.42)

        XCTAssertTrue(
            ModelSetupPresentation.statusText(state, language: .simplifiedChinese).contains("42%")
        )
        XCTAssertTrue(
            ModelSetupPresentation.statusText(state, language: .english).contains("42%")
        )
        XCTAssertEqual(ModelSetupPresentation.progressAccessibilityValue(state), "42%")
    }

    func testEveryFailureHasEnglishAndChineseCopy() {
        for failure in [
            ModelSetupFailure.insufficientDisk,
            .insufficientMemory,
            .network,
            .revisionMismatch,
            .verification,
            .activation,
            .generic,
        ] {
            XCTAssertFalse(
                ModelSetupPresentation.errorText(failure, language: .english).isEmpty,
                failure.rawValue
            )
            XCTAssertFalse(
                ModelSetupPresentation.errorText(failure, language: .simplifiedChinese).isEmpty,
                failure.rawValue
            )
        }
    }

    func testProgressHasAccessibleLabelAndValueAndNoCustomMotion() throws {
        let url = Self.repositoryRoot.appendingPathComponent("macosApp/src/Model/ModelSetupViews.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains(".accessibilityLabel("))
        XCTAssertTrue(source.contains(".accessibilityValue("))
        XCTAssertFalse(source.contains("withAnimation"))
        XCTAssertFalse(source.contains(".animation("))
    }

    func testBothAIFeaturesRenderTheSharedSetupView() throws {
        let agent = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("macosApp/src/Agent/AgentTabView.swift"),
            encoding: .utf8
        )
        let naming = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "macosApp/src/AutoNaming/AutoNamingPreviewView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(agent.contains("ModelSetupInlineCard("))
        XCTAssertTrue(agent.contains("modelSetup.activeModelSupportsAgent"))
        XCTAssertTrue(naming.contains("ModelSetupPanel("))
        XCTAssertTrue(naming.contains("modelSetup.isAIReady"))
    }

    private func makeState(
        phase: ModelSetupPhase,
        fraction: Double
    ) -> ModelSetupState {
        ModelSetupState(
            info: ModelSetupInfo.make(for: .compact2B),
            phase: phase,
            fractionCompleted: fraction,
            downloadedBytes: 0,
            failure: nil,
            detail: nil
        )
    }
}
