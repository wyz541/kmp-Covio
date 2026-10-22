import Darwin
import Foundation
import ObjectiveC

/// PowerUI 只读能力与旁路状态。生产实现动态加载私有框架，测试注入假实现。
protocol PowerUIChargeReading: Sendable {
    func capability() -> PowerUICapability
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
/// 只读取能力、状态，并调用 `disableMCL` 完成恢复。Covio 不通过这个类设置低电量目标。
final class SystemPowerUIChargeClient: PowerUIChargeReading, @unchecked Sendable {
    private typealias AllocFunction = @convention(c) (AnyClass, Selector) -> AnyObject
    private typealias InitFunction = @convention(c) (AnyObject, Selector, NSString) -> AnyObject
    private typealias BoolFunction = @convention(c) (AnyObject, Selector) -> Bool
    private typealias ObjectFunction = @convention(c) (AnyObject, Selector) -> AnyObject?
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
    private static let statusSelector = NSSelectorFromString("status")
    private static let disableSelector = NSSelectorFromString("disableMCL:")

    private let lock = NSLock()
    private var client: AnyObject?
    private var attemptedLoad = false

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
