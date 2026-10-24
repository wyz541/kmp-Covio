import CoreGraphics
import Darwin
import Foundation

enum ClosedLidBrightnessAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }

    var reason: String? {
        guard case let .unavailable(reason) = self else { return nil }
        return reason
    }
}

struct ClosedLidDisplayState: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let isOnline: Bool
    let isActive: Bool
    let isAsleep: Bool

    var allowsCapture: Bool {
        isOnline && isActive && !isAsleep
    }

    var diagnosticDescription: String {
        "display=\(displayID) online=\(isOnline.intValue) active=\(isActive.intValue) asleep=\(isAsleep.intValue)"
    }
}

enum ClosedLidBrightnessBackendError: Error, Equatable, LocalizedError {
    case unsupportedOperatingSystem(Int)
    case unsupportedArchitecture
    case frameworkUnavailable
    case missingSymbol(String)
    case noBuiltInDisplay
    case readFailed(Int32)
    case writeFailed(Int32)
    case invalidBrightness(Float)

    var errorDescription: String? {
        switch self {
        case let .unsupportedOperatingSystem(major):
            "DisplayServices brightness is not verified on macOS \(major)"
        case .unsupportedArchitecture:
            "DisplayServices brightness is only enabled for Apple Silicon"
        case .frameworkUnavailable:
            "DisplayServices.framework is unavailable"
        case let .missingSymbol(name):
            "DisplayServices is missing \(name)"
        case .noBuiltInDisplay:
            "No built-in display is available"
        case let .readFailed(code):
            "DisplayServicesGetBrightness failed (\(code))"
        case let .writeFailed(code):
            "DisplayServicesSetBrightness failed (\(code))"
        case let .invalidBrightness(value):
            "Brightness readback is outside 0...1 (\(value))"
        }
    }
}

protocol ClosedLidBrightnessBackend: AnyObject {
    var availability: ClosedLidBrightnessAvailability { get }
    func builtInDisplayID() -> CGDirectDisplayID?
    func displayState(displayID: CGDirectDisplayID) -> ClosedLidDisplayState
    func readBrightness(displayID: CGDirectDisplayID) throws -> Float
    func setBrightness(_ brightness: Float, displayID: CGDirectDisplayID) throws
}

/// Dynamically loaded DisplayServices bridge.
///
/// The framework is private. Do not add it to the Xcode link phase. A failed
/// version, architecture, framework, or symbol check makes this backend inert.
final class DisplayServicesBrightnessBackend: ClosedLidBrightnessBackend {
    private typealias GetBrightness = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct Symbols {
        let get: GetBrightness
        let set: SetBrightness
    }

    static let verifiedMajorVersions: Set<Int> = [27]
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private let symbols: Result<Symbols, ClosedLidBrightnessBackendError>
    private let handle: UnsafeMutableRawPointer?
    let availability: ClosedLidBrightnessAvailability

    init(osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        let resolved = Self.resolve(osMajorVersion: osMajorVersion)
        symbols = resolved.symbols
        handle = resolved.handle
        switch resolved.symbols {
        case .success:
            availability = .available
        case let .failure(error):
            availability = .unavailable(error.localizedDescription)
        }
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    func builtInDisplayID() -> CGDirectDisplayID? {
        firstBuiltInDisplay { capacity, ids, count in
            CGGetOnlineDisplayList(capacity, ids, count)
        } ?? firstBuiltInDisplay { capacity, ids, count in
            CGGetActiveDisplayList(capacity, ids, count)
        }
    }

    func displayState(displayID: CGDirectDisplayID) -> ClosedLidDisplayState {
        ClosedLidDisplayState(
            displayID: displayID,
            isOnline: CGDisplayIsOnline(displayID) != 0,
            isActive: CGDisplayIsActive(displayID) != 0,
            isAsleep: CGDisplayIsAsleep(displayID) != 0
        )
    }

    func readBrightness(displayID: CGDirectDisplayID) throws -> Float {
        let symbols = try resolvedSymbols()
        var value: Float = -1
        let result = symbols.get(displayID, &value)
        guard result == 0 else { throw ClosedLidBrightnessBackendError.readFailed(result) }
        guard value.isFinite, (0 ... 1).contains(value) else {
            throw ClosedLidBrightnessBackendError.invalidBrightness(value)
        }
        return value
    }

    func setBrightness(_ brightness: Float, displayID: CGDirectDisplayID) throws {
        let symbols = try resolvedSymbols()
        let clamped = min(max(brightness, 0), 1)
        let result = symbols.set(displayID, clamped)
        guard result == 0 else { throw ClosedLidBrightnessBackendError.writeFailed(result) }
    }

    private func resolvedSymbols() throws -> Symbols {
        try symbols.get()
    }

    private func firstBuiltInDisplay(
        using list: (
            UInt32,
            UnsafeMutablePointer<CGDirectDisplayID>?,
            UnsafeMutablePointer<UInt32>
        ) -> CGError
    ) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard list(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard list(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private static func resolve(
        osMajorVersion: Int
    ) -> (symbols: Result<Symbols, ClosedLidBrightnessBackendError>, handle: UnsafeMutableRawPointer?) {
        guard verifiedMajorVersions.contains(osMajorVersion) else {
            return (.failure(.unsupportedOperatingSystem(osMajorVersion)), nil)
        }
#if arch(arm64)
        guard let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) else {
            return (.failure(.frameworkUnavailable), nil)
        }
        guard let getPointer = dlsym(handle, "DisplayServicesGetBrightness") else {
            dlclose(handle)
            return (.failure(.missingSymbol("DisplayServicesGetBrightness")), nil)
        }
        guard let setPointer = dlsym(handle, "DisplayServicesSetBrightness") else {
            dlclose(handle)
            return (.failure(.missingSymbol("DisplayServicesSetBrightness")), nil)
        }
        return (
            .success(Symbols(
                get: unsafeBitCast(getPointer, to: GetBrightness.self),
                set: unsafeBitCast(setPointer, to: SetBrightness.self)
            )),
            handle
        )
#else
        return (.failure(.unsupportedArchitecture), nil)
#endif
    }
}

private extension Bool {
    var intValue: Int {
        self ? 1 : 0
    }
}
