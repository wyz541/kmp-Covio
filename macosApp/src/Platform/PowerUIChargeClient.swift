import Darwin
import Foundation
import ObjectiveC

/// PowerUI 能力、状态与原生 MCL 写入。生产实现动态加载私有框架。
protocol PowerUIChargeReading: Sendable {
    var minimumSupportedPercent: Int { get }
    func capability() -> PowerUICapability
    func isMCLEnabled() -> Bool?
    func currentLimit() -> Int?
    func applyLimit(_ percent: Int) -> Bool
    func bypassEngaged() -> Bool
    @discardableResult
    func disableMCL() -> Bool
}

enum PowerUICapability: Equatable, Sendable {
    case supported
    case unsupported
}

/// `PowerUISmartChargeClient` 的窄封装。
///
/// 只调用 Apple MCL 客户端公开给私有框架的窄接口。
///
/// 真机验证确认：直接偏好写入不会注册 `powerd`。客户端写入只支持 `80%` 到 `100%`。
final class SystemPowerUIChargeClient: PowerUIChargeReading, @unchecked Sendable {
    private typealias AllocFunction = @convention(c) (AnyClass, Selector) -> AnyObject
    private typealias InitFunction = @convention(c) (AnyObject, Selector, NSString) -> AnyObject
    private typealias BoolFunction = @convention(c) (AnyObject, Selector) -> Bool
    private typealias ObjectFunction = @convention(c) (AnyObject, Selector) -> AnyObject?
    private typealias UInt8ErrorFunction = @convention(c) (
        AnyObject,
        Selector,
        UnsafeMutablePointer<NSError?>?
    ) -> UInt8
    private typealias UInt64ErrorFunction = @convention(c) (
        AnyObject,
        Selector,
        UnsafeMutablePointer<NSError?>?
    ) -> UInt64
    private typealias BoolUInt8ErrorFunction = @convention(c) (
        AnyObject,
        Selector,
        UInt8,
        UnsafeMutablePointer<NSError?>?
    ) -> Bool
    private typealias BoolErrorFunction = @convention(c) (
        AnyObject,
        Selector,
        UnsafeMutablePointer<NSError?>?
    ) -> Bool

    private static let frameworkPaths = [
        "/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI",
        "/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI",
    ]
    private static let className = "PowerUISmartChargeClient"
    private static let initSelector = NSSelectorFromString("initWithClientName:")
    private static let supportedSelector = NSSelectorFromString("isMCLSupported")
    private static let enabledSelector = NSSelectorFromString("isMCLCurrentlyEnabled:")
    private static let currentLimitSelector = NSSelectorFromString("getMCLLimitWithError:")
    private static let enableSelector = NSSelectorFromString("enableMCL:")
    private static let setLimitSelector = NSSelectorFromString("setMCLLimit:error:")
    private static let statusSelector = NSSelectorFromString("status")
    private static let disableSelector = NSSelectorFromString("disableMCL:")

    private let lock = NSLock()
    private var client: AnyObject?
    private var attemptedLoad = false

    let minimumSupportedPercent = 80

    func capability() -> PowerUICapability {
        lock.withLock {
            guard let client = clientLocked(),
                  let function = boolFunction(selector: Self.supportedSelector, on: client)
            else {
                return .unsupported
            }
            return function(client, Self.supportedSelector) ? .supported : .unsupported
        }
    }

    func isMCLEnabled() -> Bool? {
        lock.withLock {
            guard let client = clientLocked(),
                  let function = errorFunction(selector: Self.enabledSelector, on: client)
            else {
                return nil
            }
            var error: NSError?
            let enabled = function(client, Self.enabledSelector, &error)
            return error == nil ? enabled != 0 : nil
        }
    }

    func currentLimit() -> Int? {
        lock.withLock {
            guard let client = clientLocked(),
                  let function = uint8ErrorFunction(selector: Self.currentLimitSelector, on: client)
            else {
                return nil
            }
            var error: NSError?
            let value = Int(function(client, Self.currentLimitSelector, &error))
            return error == nil && (1...100).contains(value) ? value : nil
        }
    }

    @discardableResult
    func applyLimit(_ percent: Int) -> Bool {
        guard (minimumSupportedPercent...100).contains(percent) else { return false }
        return lock.withLock {
            guard let client = clientLocked(),
                  let enable = boolErrorFunction(selector: Self.enableSelector, on: client),
                  let setLimit = boolUInt8ErrorFunction(selector: Self.setLimitSelector, on: client)
            else {
                return false
            }
            var error: NSError?
            guard enable(client, Self.enableSelector, &error), error == nil else { return false }
            error = nil
            return setLimit(client, Self.setLimitSelector, UInt8(percent), &error) && error == nil
        }
    }

    func bypassEngaged() -> Bool {
        lock.withLock {
            guard let client = clientLocked(),
                  let function = objectFunction(selector: Self.statusSelector, on: client),
                  let status = function(client, Self.statusSelector)
            else {
                return false
            }
            return Self.isBypassEngaged(status: status)
        }
    }

    @discardableResult
    func disableMCL() -> Bool {
        lock.withLock {
            guard let client = clientLocked(),
                  let function = boolErrorFunction(selector: Self.disableSelector, on: client)
            else {
                return false
            }
            var error: NSError?
            return function(client, Self.disableSelector, &error) && error == nil
        }
    }

    /// 读取时间线里最新事件的 `event`。没有可靠时间线时按未旁路处理。
    static func isBypassEngaged(status: Any) -> Bool {
        guard let dictionary = status as? [String: Any],
              let timeline = dictionary["Timeline"] as? [Any]
        else {
            return false
        }

        let stateEvents = Set(["BypassEngaged", "Engaged", "Ungaged", "Disabled"])
        var latest: (date: Double, event: String)?
        for item in timeline {
            guard let entry = item as? [String: Any],
                  let event = entry["event"] as? String,
                  let rawDate = entry["date"]
            else {
                continue
            }
            let date: Double?
            if let number = rawDate as? NSNumber {
                date = number.doubleValue
            } else if let text = rawDate as? String {
                date = Double(text)
            } else {
                date = nil
            }
            guard let date, date.isFinite else { continue }
            guard stateEvents.contains(event) else { continue }
            if latest == nil || date > latest!.date {
                latest = (date, event)
            }
        }
        return latest?.event.caseInsensitiveCompare("BypassEngaged") == .orderedSame
    }

    private func clientLocked() -> AnyObject? {
        if let client { return client }
        guard !attemptedLoad else { return nil }
        attemptedLoad = true

        guard Self.frameworkPaths.contains(where: { dlopen($0, RTLD_NOW) != nil }),
              let cls: AnyClass = NSClassFromString(Self.className),
              class_getInstanceMethod(cls, Self.initSelector) != nil,
              class_getInstanceMethod(cls, Self.supportedSelector) != nil,
              class_getInstanceMethod(cls, Self.enabledSelector) != nil,
              class_getInstanceMethod(cls, Self.currentLimitSelector) != nil,
              class_getInstanceMethod(cls, Self.enableSelector) != nil,
              class_getInstanceMethod(cls, Self.setLimitSelector) != nil,
              class_getInstanceMethod(cls, Self.statusSelector) != nil,
              class_getInstanceMethod(cls, Self.disableSelector) != nil,
              let allocImplementation = class_getMethodImplementation(
                object_getClass(cls),
                NSSelectorFromString("alloc")
              ),
              let initImplementation = class_getMethodImplementation(cls, Self.initSelector)
        else {
            return nil
        }

        let alloc = unsafeBitCast(allocImplementation, to: AllocFunction.self)
        let initialize = unsafeBitCast(initImplementation, to: InitFunction.self)
        let allocated = alloc(cls, NSSelectorFromString("alloc"))
        let created = initialize(allocated, Self.initSelector, "Covio" as NSString)
        client = created
        return created
    }

    private func boolFunction(selector: Selector, on client: AnyObject) -> BoolFunction? {
        guard client.responds(to: selector),
              let implementation = class_getMethodImplementation(type(of: client), selector)
        else {
            return nil
        }
        return unsafeBitCast(implementation, to: BoolFunction.self)
    }

    private func objectFunction(selector: Selector, on client: AnyObject) -> ObjectFunction? {
        guard client.responds(to: selector),
              let implementation = class_getMethodImplementation(type(of: client), selector)
        else {
            return nil
        }
        return unsafeBitCast(implementation, to: ObjectFunction.self)
    }

    private func errorFunction(selector: Selector, on client: AnyObject) -> UInt64ErrorFunction? {
        guard client.responds(to: selector),
              let implementation = class_getMethodImplementation(type(of: client), selector)
        else {
            return nil
        }
        return unsafeBitCast(implementation, to: UInt64ErrorFunction.self)
    }

    private func uint8ErrorFunction(
        selector: Selector,
        on client: AnyObject
    ) -> UInt8ErrorFunction? {
        guard client.responds(to: selector),
              let implementation = class_getMethodImplementation(type(of: client), selector)
        else {
            return nil
        }
        return unsafeBitCast(implementation, to: UInt8ErrorFunction.self)
    }

    private func boolUInt8ErrorFunction(
        selector: Selector,
        on client: AnyObject
    ) -> BoolUInt8ErrorFunction? {
        guard client.responds(to: selector),
              let implementation = class_getMethodImplementation(type(of: client), selector)
        else {
            return nil
        }
        return unsafeBitCast(implementation, to: BoolUInt8ErrorFunction.self)
    }

    private func boolErrorFunction(
        selector: Selector,
        on client: AnyObject
    ) -> BoolErrorFunction? {
        guard client.responds(to: selector),
              let implementation = class_getMethodImplementation(type(of: client), selector)
        else {
            return nil
        }
        return unsafeBitCast(implementation, to: BoolErrorFunction.self)
    }
}
