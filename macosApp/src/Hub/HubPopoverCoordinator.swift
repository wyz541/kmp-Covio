import Observation

/// 收集 Hub 内当前打开的 Popover。
///
/// Popover 使用独立窗口。指针进入 Popover 后，Hub 会收到一次指针移出事件。
/// 控制器读取这里的状态，决定是否暂停自动收起。
@MainActor
@Observable
final class HubPopoverCoordinator {
    /// 每次显式收起都会加一。打开中的 Popover 监听这个值并关闭自己。
    private(set) var dismissalRequest = 0

    /// 仍在显示的 Popover 身份。用集合避免同一内容重复报告。
    private var activeIDs: Set<String> = []

    /// 活动状态变化时通知控制器。回调持有控制器弱引用。
    @ObservationIgnored
    var onActivityChanged: ((Bool) -> Void)?

    var hasActivePopover: Bool { !activeIDs.isEmpty }

    /// 登记或注销一个 Popover。只有首个打开和最后一个关闭会通知控制器。
    func setPresented(_ presented: Bool, id: String) {
        let wasActive = hasActivePopover
        if presented {
            activeIDs.insert(id)
        } else {
            activeIDs.remove(id)
        }
        guard wasActive != hasActivePopover else { return }
        onActivityChanged?(hasActivePopover)
    }

    /// 请求所有 Popover 关闭。Hub 会等最后一个关闭后再收起。
    func requestDismissal() {
        dismissalRequest &+= 1
    }

    /// 控制器停止时清空记录。
    func reset() {
        let wasActive = hasActivePopover
        activeIDs.removeAll()
        if wasActive { onActivityChanged?(false) }
    }
}
