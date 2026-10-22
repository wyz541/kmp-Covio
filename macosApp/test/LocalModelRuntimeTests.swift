import XCTest
@testable import Covio

final class LocalModelRuntimeTests: XCTestCase {
    private actor LoadCounter {
        private(set) var value = 0

        func load() -> Int {
            value += 1
            return value
        }
    }

    func testSelectorUsesHighestSupportedTier() {
        let root = URL(fileURLWithPath: "/Models", isDirectory: true)
        let candidates = LocalModelTier.allCases.map {
            LocalModelCandidate(
                tier: $0,
                directory: root.appendingPathComponent($0.runtimeDirectoryName, isDirectory: true)
            )
        }

        XCTAssertEqual(
            LocalModelSelector.select(
                candidates: candidates,
                physicalMemoryBytes: 7 * 1_024 * 1_024 * 1_024
            )?.tier,
            .compact2B
        )
        XCTAssertEqual(
            LocalModelSelector.select(
                candidates: candidates,
                physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024
            )?.tier,
            .balanced4B
        )
        XCTAssertEqual(
            LocalModelSelector.select(
                candidates: candidates,
                physicalMemoryBytes: 32 * 1_024 * 1_024 * 1_024
            )?.tier,
            .heavy30BA3B
        )
    }

    func testRuntimeLoadsOnceAndSerializesLeases() async throws {
        let counter = LoadCounter()
        let runtime = SharedModelRuntime<Int> {
            await counter.load()
        }

        let first = try await runtime.acquire()
        let firstLoadCount = await counter.value
        XCTAssertEqual(firstLoadCount, 1)

        let secondTask = Task { try await runtime.acquire() }
        try await Task.sleep(for: .milliseconds(50))
        let blockedLoadCount = await counter.value
        XCTAssertEqual(blockedLoadCount, 1)

        await first.release()
        let second = try await secondTask.value
        XCTAssertEqual(second.resource, first.resource)
        await second.release()
    }

    func testUnloadForcesANewResourceOnTheNextLease() async throws {
        let counter = LoadCounter()
        let runtime = SharedModelRuntime<Int> {
            await counter.load()
        }

        let first = try await runtime.acquire()
        await first.release()
        await runtime.unload()

        let second = try await runtime.acquire()
        XCTAssertEqual(second.resource, 2)
        await second.release()
    }

    func testReplacingTheLoaderUnloadsBeforeTheNextModel() async throws {
        let counter = LoadCounter()
        let runtime = SharedModelRuntime<Int> {
            await counter.load()
        }
        let first = try await runtime.acquire()
        await first.release()

        await runtime.replaceLoader {
            await counter.load() + 10
        }
        let second = try await runtime.acquire()

        XCTAssertEqual(second.resource, 12)
        let loadCount = await counter.value
        XCTAssertEqual(loadCount, 2)
        await second.release()
    }

    func testModelTierCapabilitiesMatchTheSafetyDecision() {
        XCTAssertTrue(LocalModelTier.compact2B.supportsAgentToolCalling)
        XCTAssertTrue(LocalModelTier.balanced4B.supportsAgentToolCalling)
        XCTAssertTrue(LocalModelTier.highQuality8B.supportsAgentToolCalling)
        XCTAssertFalse(LocalModelTier.heavy30BA3B.supportsAgentToolCalling)
    }

    func testBundledConfigurationSelectsAnAvailableTierForHardware() throws {
        let root = URL(fileURLWithPath: "/Applications/Covio.app/Contents/Resources")
        let available = Set([
            LocalModelTier.compact2B.runtimeDirectoryName,
            LocalModelTier.balanced4B.runtimeDirectoryName,
            LocalModelTier.highQuality8B.runtimeDirectoryName,
        ])
        let configuration = try XCTUnwrap(
            NamingModelConfiguration.bundled(
                resourceDirectory: root,
                environment: [:],
                physicalMemoryBytes: 24 * 1_024 * 1_024 * 1_024,
                fileExists: { available.contains($0.lastPathComponent) }
            )
        )

        XCTAssertEqual(configuration.tier, .highQuality8B)
        XCTAssertEqual(configuration.modelDirectory.lastPathComponent, "Qwen3VL-8B-Instruct-4bit")
    }
}
