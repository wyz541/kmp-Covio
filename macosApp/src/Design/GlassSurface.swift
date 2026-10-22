import AppKit
import SwiftUI

/// 玻璃底材的模式。
///
/// 底板按 Apple 的官方做法取：`NSVisualEffectView` 加**语义材质**。
/// 语义材质就是按它所属的界面元素命名的那一组。
///
/// AppKit 头文件把这条规则写死了：
///
/// - `NSVisualEffectMaterialAppearanceBased` 标了 `API_DEPRECATED`，
///   注释是「You should instead choose an appropriate semantic material.」
/// - `Light`、`Dark`、`MediumLight`、`UltraDark` 这一组标着
///   「Materials with specific looks. You should instead choose an appropriate semantic material.」
/// - 剩下的每个材质都按它所属的元素命名并说明。
///
/// 浮在桌面上的面板对应 `.hudWindow`。头文件的说明是
/// 「The material used as the background of heads-up display (HUD) windows.」
///
/// SwiftUI 的 `Material` 没有面板这一档，只有 `ultraThin` 到 `ultraThick` 和 `bar`。
/// 所以面板底材走 `NSVisualEffectView`。材质原样使用：不乘不透明度倍率，不加着色。
///
/// 面板有三层：
///
/// 1. 一块铺满面板的**内容层**，把桌面与工作区分开。
/// 2. 卡片叠在内容层上，自己走 `.clear`，只加一层薄高光，不重复模糊。
/// 3. 导航层叠在内容层上方，用超薄材质模糊背后的内容。
///
/// 真机对照：把一个带文字的 TextEdit 窗口摆在面板下面。整片面板区域的文字
/// 都被抹成灰条。模糊来自底板，不是来自卡片本身。
///
/// 所以 `.clear` 只有在**底下已经有模糊**时才成立。单独把 `.clear` 压在桌面上，
/// 背后窗口的文字会原样透上来，与卡片自己的正文撞在一起。
///
/// 现在的分派：
///
/// | 位置 | 底材 | 理由 |
/// | --- | --- | --- |
/// | 内容层 | `.system` + `.hudWindow` | 面板底材，用系统给的语义材质 |
/// | 内容区的卡片 | `.clear` | 叠在内容层上，不重复模糊，保留 Liquid Glass 的亮边 |
/// | 导航层 | `.ultraThin` | 模糊背后的内容，不带边框 |
///
/// 内容层与导航层都不带边框。卡片保留 Liquid Glass 自带的亮边。
///
/// 内容层与导航层都不加着色：真机实测，压平传递曲线的是那层黑色着色，
/// 见 [plateTintOpacity]。
/// 卡片只带一点点色相，见 `MacTheme.tintedCardOpacity`。
///
/// 这几个模式也用于真机对照：同一个面板换底材截图，挑出最接近目标的那个。
/// 圆角、间距与排版在几种模式下完全一致，只有底材不同。
enum GlassSurfaceMode: String, CaseIterable, Sendable {
    /// Liquid Glass 的标准材质。模糊到位，自带一圈镜面亮边。卡片用它。
    ///
    /// 真机实测（2026-10-17，满量程渐变垫在背后，浅色外观，着色 0）：
    /// 桌面亮度从 24 级变到 207 级，面板从 152 级走到 243 级，斜率 0.50。
    /// 加一层黑 0.4 着色以后曲线被压到 62 到 118 级，斜率掉到 0.28 —— 那才是死灰板。
    case glass
    /// Liquid Glass 的清透材质。几乎不模糊，只加薄高光。叠在模糊上面的模块用它。
    case clear
    /// 常规毛玻璃。对照用。斜率 0.34。
    case material
    /// 超薄毛玻璃。对照用。斜率 0.53。不带边框。
    case ultraThin
    /// 系统材质（`NSVisualEffectView`）。面板底材走这一条。
    ///
    /// 材质种类由 [plateMaterial] 定。系统材质只做半透明模糊，不自适应外观，
    /// 也不带 Liquid Glass 的亮边。
    case system

    /// 当前生效的模式。
    ///
    /// 只在主线程改：界面全部在主线程构建。
    /// 调试构建可以用环境变量 `COVIO_GLASS_SURFACE` 覆盖，便于同一次构建换材质截图。
    ///
    /// 这里只影响没显式传 `mode` 的调用点，也就是叠在底板上的那些卡片。
    @MainActor static var current: GlassSurfaceMode = .clear

    /// `.system` 模式用的材质。
    ///
    /// 取 `.hudWindow`：AppKit 头文件的说明是
    /// 「The material used as the background of heads-up display (HUD) windows.」
    /// 面板正是浮在桌面上的 HUD 窗口。
    ///
    /// 它是语义材质里最透的一档，真机实测（2026-10-17，浅色外观，满量程渐变垫在背后）
    /// 传递曲线是 `0.25·桌面 + 149`。会模糊的材质里没有比它更透的。
    ///
    /// 调试构建可以用 `COVIO_PLATE_MATERIAL` 换成别的语义材质对照，
    /// 认得出的名字见 [material(named:)]。
    @MainActor static var plateMaterial: NSVisualEffectView.Material = .hudWindow

    /// 材质名字到系统材质的对照。认不出的名字返回 nil。
    static func material(named name: String) -> NSVisualEffectView.Material? {
        switch name {
        case "hudWindow": return .hudWindow
        case "popover": return .popover
        case "menu": return .menu
        case "sidebar": return .sidebar
        case "fullScreenUI": return .fullScreenUI
        case "contentBackground": return .contentBackground
        case "windowBackground": return .windowBackground
        case "underWindowBackground": return .underWindowBackground
        case "underPageBackground": return .underPageBackground
        case "titlebar": return .titlebar
        case "headerView": return .headerView
        case "sheet": return .sheet
        case "toolTip": return .toolTip
        default: return nil
        }
    }

    /// 底板的着色不透明度。取 0 到 1 的黑色。默认 0，不加着色。
    ///
    /// 为什么取 0：真机实测（2026-10-17，满量程黑白渐变垫在面板背后，浅色外观）。
    /// 同一种 Liquid Glass，加一层黑 0.4 着色以后曲线被压到 62 到 118 级，
    /// 斜率从 0.50 掉到 0.28。工作台此前看起来像一块死灰板，压平曲线的是这层着色。
    ///
    /// 取值由**传递曲线**定，不由单点差定。桌面亮度分箱，取每箱里面板的平均亮度，
    /// 得到一条线。线的斜率就是底材的有效透明度，与桌面内容无关。
    ///
    /// | 底材 | 斜率 | 面板亮度范围 |
    /// | --- | --- | --- |
    /// | 控制中心 | 0.71 | 66 → 196 |
    /// | `.glass`，不着色 | 0.50 | 152 → 243 |
    /// | `.ultraThin` | 0.49 | 132 → 221 |
    /// | `.glass`，黑 0.4 着色 | 0.28 | 62 → 118 |
    ///
    /// 调试构建可以用 `COVIO_PLATE_TINT` 覆盖。真机对照用它扫值。
    @MainActor static var plateTintOpacity: Double = 0

    /// 底板用的底材。取 `.system`：面板底材用系统给的语义材质，见 [plateMaterial]。
    ///
    /// 为什么不用 `.glass`：Liquid Glass 自带一圈镜面亮边。控制中心的**模块**有亮边，
    /// **内容层**没有。真机对照（2026-10-17）：把旧的上下两板左上角放大，内容板
    /// 沿上边缘有一条浅蓝亮线，控制中心的底板边缘是干净的。
    ///
    /// 卡片的亮边保留：卡片走 `.clear` 玻璃，与控制中心的模块一样带边。
    ///
    /// 调试构建可以用 `COVIO_PLATE_MODE` 覆盖，用来复核别的底材。
    @MainActor static var plateMode: GlassSurfaceMode = .system

    /// 顶栏功能层用的底材。默认 `.ultraThin`，参考 macOS 26 Tahoe 的 Apple Maps。
    ///
    /// 顶栏叠在内容层上方，所以超薄材质会模糊背后的内容。顶栏不带边框与投影，
    /// 层次由材质边界与内容移动给。系统开启降低透明度时，材质自动变得更实。
    ///
    /// 调试构建可以用 `COVIO_TOPBAR_MODE` 覆盖。
    @MainActor static var topBarMode: GlassSurfaceMode = .ultraThin

    /// 底板用的着色。不透明度是 0 时返回 nil，玻璃走原样。
    @MainActor static var plateTint: Color? {
        plateTintOpacity > 0 ? .black.opacity(plateTintOpacity) : nil
    }

    /// 从环境变量取覆盖值。取值不认识时保持原样。
    @MainActor static func applyEnvironmentOverride() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let raw = env["COVIO_GLASS_SURFACE"], let mode = GlassSurfaceMode(rawValue: raw) {
            current = mode
            NSLog("Covio 玻璃底材被环境变量改成 \(mode.rawValue)。")
        }
        if let raw = env["COVIO_PLATE_TINT"], let value = Double(raw) {
            plateTintOpacity = min(max(value, 0), 1)
            NSLog("Covio 底板着色被环境变量改成 \(plateTintOpacity)。")
        }
        if let raw = env["COVIO_PLATE_MODE"], let mode = GlassSurfaceMode(rawValue: raw) {
            plateMode = mode
            NSLog("Covio 底板底材被环境变量改成 \(mode.rawValue)。")
        }
        if let raw = env["COVIO_TOPBAR_MODE"], let mode = GlassSurfaceMode(rawValue: raw) {
            topBarMode = mode
            NSLog("Covio 顶栏板底材被环境变量改成 \(mode.rawValue)。")
        }
        if let raw = env["COVIO_PLATE_MATERIAL"], let material = GlassSurfaceMode.material(named: raw) {
            plateMaterial = material
            NSLog("Covio 底板材质被环境变量改成 \(raw)。")
        }
        #endif
    }
}

extension View {
    /// 给视图加一层玻璃底材与圆角。
    ///
    /// 圆角由调用方从 `MacTheme` 取，不在这里写数值。
    /// `tint` 给玻璃上色，用于首页的彩色卡片。
    @MainActor
    func glassSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        interactive: Bool = false,
        mode: GlassSurfaceMode? = nil
    ) -> some View {
        // 默认值在主线程取：`current` 是主线程隔离的，不能写在默认参数里。
        modifier(
            GlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                interactive: interactive,
                mode: mode ?? GlassSurfaceMode.current
            )
        )
    }
}

/// 玻璃底材。所有模式共用圆角。
private struct GlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    let mode: GlassSurfaceMode

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// 把着色与交互开关套到玻璃变体上。
    private func variant(_ base: Glass) -> Glass {
        let tinted = tint.map { base.tint($0) } ?? base
        return interactive ? tinted.interactive() : tinted
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch mode {
        case .glass:
            content.glassEffect(variant(.regular), in: .rect(cornerRadius: cornerRadius))
        case .clear:
            content.glassEffect(variant(.clear), in: .rect(cornerRadius: cornerRadius))
        case .material:
            // 毛玻璃模式没有原生着色，用一层半透明填充代替。
            // 材质原样使用，不乘不透明度倍率。
            content
                .background(shape.fill(tint ?? .clear))
                .background(shape.fill(.regularMaterial))
        case .ultraThin:
            content
                .background(shape.fill(tint ?? .clear))
                .background(shape.fill(.ultraThinMaterial))
        case .system:
            content
                .background(shape.fill(tint ?? .clear))
                .background(SystemBackdrop(material: GlassSurfaceMode.plateMaterial, cornerRadius: cornerRadius))
        }
    }
}

/// 系统材质做的半透明模糊底。
///
/// `blendingMode` 取 `.behindWindow`：模糊的是窗口背后的桌面。
/// 面板是无边框透明窗口，所以这一层看到的就是桌面。
///
/// `state` 取 `.active`。默认的 `.followsWindowActiveState` 会在应用不是前台时
/// 把材质调淡，面板是 `.nonactivatingPanel`，点它不激活应用，会被误判成非前台。
private struct SystemBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.layer?.cornerRadius = cornerRadius
    }
}
