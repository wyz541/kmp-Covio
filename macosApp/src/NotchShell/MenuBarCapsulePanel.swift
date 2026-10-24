import AppKit
import SwiftUI

/// 菜单栏上的品牌胶囊窗口。
///
/// macOS 的状态项位置由系统排，居中不了，刘海区也放不下。所以自己画一个：
/// 一个无边框浮层窗口，`level = .statusBar`，只包住胶囊加一圈悬停余量。
///
/// **窗口只包住胶囊。** 铺满菜单栏会挡住系统菜单项与其它应用的状态项。
/// 所以这里按胶囊的实测宽度开窗，宽度取 `fittingSize`，不写死。
///
/// 它自己不接受键盘。作用有两个：报告指针进入，以及响应点击。
@MainActor
final class MenuBarCapsulePanel: ShellPanel {
    /// 指针进入胶囊。与热区同一个事件，都让挂帘展开。
    var onPointerEnter: (() -> Void)?
    /// 指针离开。用于收起悬停态。
    var onPointerExit: (() -> Void)?
    /// 点击胶囊。挂帘打开时收起，否则打开。
    var onClick: (() -> Void)?
    /// 右键或 Control 点击胶囊。打开与状态项相同的菜单。
    var onSecondaryClick: (() -> Void)?

    private let host: NSHostingView<MenuBarCapsule>
    private let container = CapsuleContainerView()
    /// 胶囊本身的尺寸，不含悬停余量。
    private(set) var capsuleSize: CGSize

    init() {
        let host = NSHostingView(rootView: MenuBarCapsule(isHovered: false))
        let size = Self.measuredCapsuleSize(of: host)
        self.host = host
        self.capsuleSize = size
        super.init(contentRect: Self.windowRect(for: size, on: nil))

        ignoresMouseEvents = false
        container.inset = HubMetrics.menuBarCapsuleHoverInset
        host.translatesAutoresizingMaskIntoConstraints = true
        container.addSubview(host)
        contentView = container
        container.autoresizingMask = [.width, .height]

        container.onPointerEnter = { [weak self] in self?.onPointerEnter?() }
        container.onPointerExit = { [weak self] in self?.onPointerExit?() }
        container.onClick = { [weak self] in self?.onClick?() }
        container.onSecondaryClick = { [weak self] in self?.onSecondaryClick?() }
    }

    /// 量胶囊的自然尺寸。宿主视图还没上屏时量出来是 0，回落到兜底值。
    ///
    /// 不给宽度设下限：胶囊宽度直接决定窗口宽度，多出来的部分会变成胶囊与刘海
    /// 之间的空隙，`ScreenGeometry.capsuleNotchGap` 就不再是 6 点。
    private static func measuredCapsuleSize(of host: NSView) -> CGSize {
        let measured = host.fittingSize
        return CGSize(
            width: measured.width > 0 ? measured.width : fallbackCapsuleWidth,
            height: measured.height > 0 ? measured.height : HubMetrics.menuBarCapsuleHeight
        )
    }

    /// 实测失败时的兜底宽度。图标 18 点，四周留一点命中余量。
    private static let fallbackCapsuleWidth: CGFloat = 24

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MenuBarCapsulePanel 只支持代码创建")
    }

    /// 胶囊不接受键盘，也不该抢走 Hub 的 key 状态。
    override var canBecomeKey: Bool { false }

    /// 换悬停态。悬停只改底色，不改尺寸。
    func setHovered(_ hovered: Bool) {
        host.rootView = MenuBarCapsule(isHovered: hovered)
    }

    /// 把窗口挪到某块屏幕的菜单栏上。显示器变化与菜单栏显隐变化时调用。
    func place(on geometry: ScreenGeometry) {
        setFrame(Self.windowRect(for: capsuleSize, on: geometry), display: true)
        container.needsLayout = true
    }

    /// 窗口矩形：胶囊矩形四周各外扩 `menuBarCapsuleHoverInset` 点。
    static func windowRect(for capsule: CGSize, on geometry: ScreenGeometry?) -> CGRect {
        let inset = HubMetrics.menuBarCapsuleHoverInset
        guard let geometry else {
            return CGRect(origin: .zero, size: capsule).insetBy(dx: -inset, dy: -inset)
        }
        return geometry
            .menuBarCapsuleRect(capsuleWidth: capsule.width, capsuleHeight: capsule.height)
            .insetBy(dx: -inset, dy: -inset)
    }
}

/// 胶囊窗口的内容视图。窗口尺寸由它定，胶囊摆在正中间。
///
/// 不能直接把 `NSHostingView` 当 `contentView`：那样 AppKit 会把窗口的内容尺寸
/// 绑到 SwiftUI 视图的内在尺寸上。实测过一次，窗口被缩成胶囊的自然尺寸并贴到
/// 左上角，`setFrame` 与 `place(on:)` 全部白设，胶囊压在刘海边上。
///
/// 跟踪区放在这一层，不放宿主视图：悬停余量那几点也要算「指针在胶囊上」。
///
/// `NSPanel` 的 `mouseEntered` 要等指针动一次才来，而菜单栏那一条很薄，
/// 指针可能停进去就不再动。所以用 `.activeAlways` 的 tracking area。
@MainActor
private final class CapsuleContainerView: NSView {
    var onPointerEnter: (() -> Void)?
    var onPointerExit: (() -> Void)?
    var onClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    /// 内容四周留出的悬停余量。
    var inset: CGFloat = 0

    private var trackingArea: NSTrackingArea?

    /// 菜单栏那一条很薄，指针往往是从别的应用切过来时直接落上去的。
    /// 不接受「第一次点击」的话，用户得先点一下再点一下。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 鼠标事件一律由这一层接。宿主视图在上面，不接管点击。
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    /// 胶囊居中：四周各让出 `inset`。
    override func layout() {
        super.layout()
        subviews.first?.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExit?()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if event.modifierFlags.contains(.control) {
            onSecondaryClick?()
        } else {
            onClick?()
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onSecondaryClick?()
    }
}
