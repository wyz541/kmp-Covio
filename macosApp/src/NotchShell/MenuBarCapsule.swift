import SwiftUI

/// 菜单栏上的品牌入口。合同 `component/tray-icon` 的收起态。
///
/// 使用与次级状态项相同的玻璃吊卡图标。悬停时轻微降透明度。
struct MenuBarCapsule: View {
    let isHovered: Bool

    var body: some View {
        Image(nsImage: CovioStatusIcon.makeImage())
            .resizable()
            .interpolation(.high)
            .frame(width: CovioStatusIcon.pointSize, height: CovioStatusIcon.pointSize)
            .opacity(isHovered ? 0.82 : 1)
            .frame(height: HubMetrics.menuBarCapsuleHeight)
            .contentShape(Rectangle())
        .accessibilityLabel(Self.brandName)
    }

    /// 品牌名是专有名词，不进合同。合同里 `copy/tray/*` 是菜单项的文案。
    static let brandName = "Covio"
}
