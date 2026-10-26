import XCTest
@testable import Covio

final class TwoFingerSwipeRecognizerTests: XCTestCase {
    private func frame(
        _ fingerCount: Int = 2,
        x: Double = 0,
        y: Double,
        at timestamp: TimeInterval
    ) -> TouchFrame {
        TouchFrame(
            fingerCount: fingerCount,
            meanNormalizedX: x,
            meanNormalizedY: y,
            timestamp: timestamp
        )
    }

    func testRecognizesOneFastVerticalSwipeDown() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(y: 0.20, at: 1.00)))
        XCTAssertTrue(recognizer.process(frame(y: 0.45, at: 1.15)))
    }

    func testOneContinuousContactTriggersOnlyOnce() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(y: 0.20, at: 1.00)))
        XCTAssertTrue(recognizer.process(frame(y: 0.45, at: 1.15)))
        XCTAssertFalse(recognizer.process(frame(y: 0.70, at: 1.25)))
    }

    func testUpwardMotionDoesNotTrigger() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(y: 0.70, at: 1.00)))
        XCTAssertFalse(recognizer.process(frame(y: 0.40, at: 1.15)))
    }

    func testSlightlyAngledSwipeStillTriggers() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(x: 0.20, y: 0.20, at: 1.00)))
        XCTAssertTrue(recognizer.process(frame(x: 0.32, y: 0.45, at: 1.15)))
    }

    func testHorizontalMotionDoesNotTrigger() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(x: 0.20, y: 0.20, at: 1.00)))
        XCTAssertFalse(recognizer.process(frame(x: 0.40, y: 0.45, at: 1.15)))
    }

    func testOrdinaryDownwardScrollDoesNotTrigger() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(y: 0.35, at: 1.00)))
        XCTAssertFalse(recognizer.process(frame(y: 0.39, at: 1.35)))
    }

    func testThreeFingerMotionDoesNotTrigger() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(3, y: 0.20, at: 1.00)))
        XCTAssertFalse(recognizer.process(frame(3, y: 0.60, at: 1.15)))
    }

    func testSlowMotionDoesNotTrigger() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(y: 0.20, at: 1.00)))
        XCTAssertFalse(recognizer.process(frame(y: 0.45, at: 1.60)))
    }

    func testCooldownDoesNotQueueARejectedGesture() {
        let configuration = TwoFingerSwipeConfiguration(cooldown: 0.60)
        var recognizer = TwoFingerSwipeRecognizer(configuration: configuration)

        XCTAssertFalse(recognizer.process(frame(y: 0.10, at: 1.00)))
        XCTAssertTrue(recognizer.process(frame(y: 0.35, at: 1.15)))
        XCTAssertFalse(recognizer.process(frame(0, y: 0, at: 1.20)))

        XCTAssertFalse(recognizer.process(frame(y: 0.10, at: 1.30)))
        XCTAssertFalse(recognizer.process(frame(y: 0.40, at: 1.45)))
        XCTAssertFalse(recognizer.process(frame(y: 0.80, at: 1.70)))
    }

    func testNewContactAfterCooldownCanTrigger() {
        let configuration = TwoFingerSwipeConfiguration(cooldown: 0.60)
        var recognizer = TwoFingerSwipeRecognizer(configuration: configuration)

        XCTAssertFalse(recognizer.process(frame(y: 0.10, at: 1.00)))
        XCTAssertTrue(recognizer.process(frame(y: 0.35, at: 1.15)))
        XCTAssertFalse(recognizer.process(frame(0, y: 0, at: 1.20)))

        XCTAssertFalse(recognizer.process(frame(y: 0.10, at: 1.80)))
        XCTAssertTrue(recognizer.process(frame(y: 0.35, at: 1.95)))
    }

    func testCalibratedBuiltInSwipeSamplesTrigger() {
        let samples: [(startX: Double, endX: Double, startY: Double, endY: Double, duration: Double)] = [
            (0.4077, 0.3755, 0.2034, 0.3717, 0.144),
            (0.4604, 0.3332, 0.1936, 0.4823, 0.136),
            (0.4955, 0.4597, 0.1674, 0.3823, 0.144),
        ]

        for sample in samples {
            var recognizer = TwoFingerSwipeRecognizer()
            XCTAssertFalse(
                recognizer.process(
                    frame(x: sample.startX, y: sample.startY, at: 1.00)
                )
            )
            XCTAssertTrue(
                recognizer.process(
                    frame(
                        x: sample.endX,
                        y: sample.endY,
                        at: 1.00 + sample.duration
                    )
                )
            )
        }
    }

    func testCalibratedBuiltInScrollSamplesDoNotTrigger() {
        let samples: [(startX: Double, endX: Double, startY: Double, endY: Double, duration: Double)] = [
            (0.4385, 0.4730, 0.4391, 0.2824, 0.392),
            (0.4443, 0.4447, 0.3221, 0.3485, 0.384),
            (0.4445, 0.4451, 0.3788, 0.3767, 0.024),
            (0.4796, 0.4722, 0.3319, 0.3714, 0.944),
        ]

        for sample in samples {
            var recognizer = TwoFingerSwipeRecognizer()
            XCTAssertFalse(
                recognizer.process(
                    frame(x: sample.startX, y: sample.startY, at: 1.00)
                )
            )
            XCTAssertFalse(
                recognizer.process(
                    frame(
                        x: sample.endX,
                        y: sample.endY,
                        at: 1.00 + sample.duration
                    )
                )
            )
        }
    }

    func testParsesNormalizedCoordinatesFromTwoTouchRecords() {
        var bytes = [UInt8](repeating: 0, count: TouchFrame.bytesPerTouch * 2)
        bytes.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(
                of: Float(0.20),
                toByteOffset: TouchFrame.normalizedXOffset,
                as: Float.self
            )
            buffer.storeBytes(
                of: Float(0.30),
                toByteOffset: TouchFrame.normalizedYOffset,
                as: Float.self
            )
            let second = TouchFrame.bytesPerTouch
            buffer.storeBytes(
                of: Float(0.40),
                toByteOffset: second + TouchFrame.normalizedXOffset,
                as: Float.self
            )
            buffer.storeBytes(
                of: Float(0.50),
                toByteOffset: second + TouchFrame.normalizedYOffset,
                as: Float.self
            )
        }

        let frame = bytes.withUnsafeBytes { buffer in
            TouchFrame.parse(
                touches: buffer.baseAddress,
                count: 2,
                timestamp: 12.5
            )
        }

        XCTAssertEqual(frame.fingerCount, 2)
        XCTAssertEqual(frame.meanNormalizedX, 0.30, accuracy: 0.0001)
        XCTAssertEqual(frame.meanNormalizedY, 0.40, accuracy: 0.0001)
        XCTAssertEqual(frame.timestamp, 12.5)
    }

    func testInvalidTouchCountResetsTheFrame() {
        var bytes = [UInt8](repeating: 0, count: TouchFrame.bytesPerTouch)
        let frame = bytes.withUnsafeMutableBytes { buffer in
            TouchFrame.parse(
                touches: buffer.baseAddress,
                count: Int32(TouchFrame.maximumTouches + 1),
                timestamp: 12.5
            )
        }

        XCTAssertEqual(frame.fingerCount, 0)
    }
}
