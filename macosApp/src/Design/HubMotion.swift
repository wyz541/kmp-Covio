import Foundation

/// Hub 的动效参数。
///
/// 数值的权威是设计合同的 `token/motion/*`，由
/// `scripts/generate-contract-constants.py` 生成到 `ContractMotion`。
/// 这里保留一层语义命名，便于按用途取用。
/// `ContractConstantsTests` 逐条比对两边，防止漂移。
enum HubMotion {
    /// Hub 展开：220 至 280 毫秒，弹性曲线。
    static let expandRange: ClosedRange<TimeInterval> = 0.220...0.280
    static let expand: TimeInterval = ContractMotion.tokenMotionHubExpand.seconds

    /// Hub 收起：160 至 220 毫秒，缓出曲线。
    static let collapseRange: ClosedRange<TimeInterval> = 0.160...0.220
    static let collapse: TimeInterval = ContractMotion.tokenMotionHubCollapse.seconds

    /// 页签切换：160 毫秒，横向滑动加淡入。
    static let tabSwitch: TimeInterval = ContractMotion.tokenMotionTabSwitch.seconds

    /// 截图捕获：650 毫秒。
    static let screenshotCapture: TimeInterval = ContractMotion.tokenMotionScreenshotCapture.seconds

    /// 截图复制：1200 毫秒提示。
    static let screenshotCopy: TimeInterval = ContractMotion.tokenMotionScreenshotCopy.seconds

    /// 文件焦点切换：120 毫秒；减弱动态效果时 80 毫秒。
    static let fileFocusSwitch: TimeInterval = ContractMotion.tokenMotionFileFocusSwitch.seconds
    static let fileFocusSwitchReduced: TimeInterval =
        ContractMotion.tokenMotionFileFocusSwitch.reducedSeconds ?? 0.08

    /// 传输开始：180 毫秒。
    static let transferStart: TimeInterval = ContractMotion.tokenMotionTransferStart.seconds

    /// 传输完成：240 毫秒。
    static let transferComplete: TimeInterval = ContractMotion.tokenMotionTransferComplete.seconds

    /// 错误出现：160 毫秒。
    static let errorAppear: TimeInterval = ContractMotion.tokenMotionErrorAppear.seconds

    /// 减弱动态效果：120 毫秒，只改透明度。
    static let reducedMotion: TimeInterval = ContractMotion.tokenMotionReducedMotion.seconds

    /// 指针移出 Hub 后收起的等待时间。
    static let pointerExitCollapseDelay: TimeInterval = ContractMotion.tokenMotionPointerExitCollapse.seconds

    /// 换页签后多久内，指针不再触发切换。
    /// 合同没有这枚令牌，取值按「指针扫过顶栏只切一次」的手感定。
    static let hoverCooldown: TimeInterval = 0.25

    /// 呼吸灯一次亮灭的时长。合同没有这枚令牌，取值按肉眼可见的缓慢呼吸定。
    static let pulse: TimeInterval = 1.2

    /// 生效的展开时长。
    static func expandDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedMotion : expand
    }

    /// 生效的收起时长。
    static func collapseDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedMotion : collapse
    }
}
