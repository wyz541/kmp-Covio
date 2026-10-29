import AppKit
import SwiftUI

/// 设计令牌到 SwiftUI 的映射。
///
/// 取值全部来自 `ContractTokens.swift`，那份由脚本从设计合同生成。
/// 这一层只做两件事：十六进制转颜色，浅色深色合成一个动态颜色。
/// 不在这里写任何字面量色值。
enum MacTheme {
    // MARK: - 颜色

    /// 页面底色。
    static let canvas = color(ContractColors.tokenColorCanvas)
    /// 卡片与窗口表面。
    static let surface = color(ContractColors.tokenColorSurface)
    /// 卡片材质填充。半透明，压在玻璃模糊上面，桌面能透过来。
    ///
    /// 合同 `token/color/material-thin`。控制中心的模块就是这样：模糊打底，
    /// 上面一层半透明填充。不透明的 `surface` 会把模糊整个盖住。
    static let material = color(ContractColors.tokenColorMaterialThin)
    /// 着色卡片的填充透明度。
    ///
    /// 首页的彩色卡片用色值乘这个透明度，叠在玻璃上面，给每张卡片一个身份色
    /// （`token/color/widget-tint-*`：琥珀、薄荷、天蓝、杏、玫瑰、石板）。
    ///
    /// 这个数是实测定的，不是合同的值。合同里最淡的一档是 `0.62`。
    ///
    /// 控制中心的模块几乎不加填充。按整块矩形取平均，模块内只比模块缝亮 16 到 34 级。
    /// 工作台在 `0.45` 下卡片比底板缝亮 46 到 50 级，面板内部自己就有一倍的反差，
    /// 读起来是「灰板上摆白板」。见 `#124` 证据 7。
    ///
    /// 取 `0.1` 让色相还看得见，同时卡片与底板的差落到控制中心的量级。
    ///
    /// 合同里 `widget-tint-*` 的深色取值与浅色完全相同，都是浅底。面板走深色外观以后，
    /// 这个值就成了压在暗底板上的一层亮填充。要再压淡，得先给这六个令牌补深色取值。
    ///
    /// 调试构建可以用 `COVIO_CARD_TINT` 覆盖，真机对照用它扫值。
    @MainActor static var tintedCardOpacity: CGFloat = 0.1
    /// 抬起的表面。
    static let elevated = color(ContractColors.tokenColorElevated)
    /// 原生控件默认填充。
    static let controlFill = color(ContractColors.tokenColorControlFill)
    /// 原生控件悬停填充。
    static let controlFillHover = color(ContractColors.tokenColorControlFillHover)
    /// 原生控件按下填充。
    static let controlFillPressed = color(ContractColors.tokenColorControlFillPressed)
    /// 分隔线与控件描边。
    static let divider = color(ContractColors.tokenColorDivider)
    /// 主文字。
    static let textPrimary = color(ContractColors.tokenColorTextPrimary)
    /// 次要文字。
    static let textSecondary = color(ContractColors.tokenColorTextSecondary)
    /// 禁用文字。
    static let disabledText = color(ContractColors.tokenColorDisabledText)
    /// 系统强调色。
    static let accent = color(ContractColors.tokenColorAccentSystem)
    /// 品牌色。选中态用它。
    static let brand = color(ContractColors.tokenColorBrand)
    /// 动作填充。
    static let actionFill = color(ContractColors.tokenColorActionFill)
    /// 键盘焦点环。
    static let focusRing = color(ContractColors.tokenColorFocusRing)
    /// 错误文字。
    static let errorText = color(ContractColors.tokenColorErrorText)
    /// 错误底色。
    static let errorBackground = color(ContractColors.tokenColorErrorBg)
    /// 警告文字。
    static let warningText = color(ContractColors.tokenColorWarningText)
    /// 警告底色。
    static let warningBackground = color(ContractColors.tokenColorWarningBg)
    /// 成功文字。
    static let successText = color(ContractColors.tokenColorSuccessText)
    /// 成功底色。
    static let successBackground = color(ContractColors.tokenColorSuccessBg)
    /// 信息底色。
    static let infoBackground = color(ContractColors.tokenColorInfoBg)
    /// 卡片与窗口阴影。
    static let shadow = color(ContractColors.tokenColorShadow)

    // MARK: - 尺寸

    /// 卡片圆角。合同 `token/radius/card`。
    static let cardRadius = ContractDimensions.tokenRadiusCard
    /// 控件圆角。合同 `token/radius/control`。
    static let controlRadius = ContractDimensions.tokenRadiusControl
    /// 输入框圆角。合同 `token/radius/small`。
    static let smallRadius = ContractDimensions.tokenRadiusSmall
    /// 按钮圆角。合同 `token/radius/medium`。
    static let mediumRadius = ContractDimensions.tokenRadiusMedium
    /// 紧凑表面圆角。合同 `token/radius/compact`。
    static let compactRadius = ContractDimensions.tokenRadiusCompact

    /// 间距 4。合同 `token/space/1`。
    static let space1 = ContractDimensions.tokenSpace1
    /// 间距 8。合同 `token/space/2`。
    static let space2 = ContractDimensions.tokenSpace2
    /// 设置行间距 12。合同 `token/space/3`。
    static let space3 = ContractDimensions.tokenSpace3
    /// 卡片内边距 16。合同 `token/space/4`。
    static let space4 = ContractDimensions.tokenSpace4
    /// 卡片组间距 20。合同 `token/space/5`。
    static let space5 = ContractDimensions.tokenSpace5
    /// 卡片间距 24。合同 `token/space/6`。
    static let space6 = ContractDimensions.tokenSpace6
    /// 页面分节间距 32。合同 `token/space/8`。
    static let space8 = ContractDimensions.tokenSpace8
    /// 页面上下留白 40。合同 `token/space/10`。
    static let space10 = ContractDimensions.tokenSpace10

    // MARK: - 转换

    /// 把一枚合同颜色令牌转成随外观变化的 SwiftUI 颜色。
    static func color(_ token: ContractColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return nsColor(hex: isDark ? token.darkHex : token.lightHex)
        })
    }

    /// 解析合同里的十六进制色值。支持 `#RRGGBB` 与 `#RRGGBBAA`。
    ///
    /// 合同里的 8 位色值把透明度放在最后两位，与 CSS 一致。
    /// 认不出的色值返回洋红色，好让错误一眼可见。
    static func nsColor(hex: String) -> NSColor {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else {
            return .magenta
        }
        let hasAlpha = text.count == 8
        let red = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// 从环境变量取卡片填充的覆盖值。取值不在 0 到 1 之间时保持原样。
    @MainActor static func applyEnvironmentOverride() {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["COVIO_CARD_TINT"],
           let value = Double(raw) {
            tintedCardOpacity = min(max(CGFloat(value), 0), 1)
            NSLog("Covio 卡片填充被环境变量改成 \(tintedCardOpacity)。")
        }
        #endif
    }
}
