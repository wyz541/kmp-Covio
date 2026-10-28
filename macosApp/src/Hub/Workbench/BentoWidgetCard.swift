import AppKit
import SwiftUI

/// 卡片第二行的内容。
///
/// 有真实数据就显示真实数据，没有就显示一个短横。
/// 打样那一行是假数据（「2 项进行中」「4 个动作」），真机不能照抄：
/// 传输队列与快捷操作还没有数据源，编一个数出来是骗人。
enum WidgetDetail {
    /// 没有数据源时的占位。它不是一个文案，所以不进合同。
    static let missing = "—"

    @MainActor
    static func text(
        for kind: String,
        runtime: AppRuntime?,
        language: AppLanguage,
        now: Date = Date()
    ) -> String {
        switch WidgetKind(rawValue: kind) {
        case .clock: clock(now: now, language: language)
        case .battery: battery()
        case .shots: shots(runtime: runtime)
        default: missing
        }
    }

    /// 「14:32 · 周三」。
    private static func clock(now: Date, language: AppLanguage) -> String {
        let time = now.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened).locale(language.locale)
        )
        let weekday = now.formatted(
            Date.FormatStyle().weekday(.abbreviated).locale(language.locale)
        )
        return "\(time) · \(weekday)"
    }

    private static func battery() -> String {
        guard let status = MacPowerSource.readBattery() else { return missing }
        return "\(status.percent)%"
    }

    @MainActor
    private static func shots(runtime: AppRuntime?) -> String {
        guard let runtime else { return missing }
        return "\(runtime.shelf.items.count)"
    }
}

/// 一块组件卡片。合同 `component/widget-card`，`nativeSize` 是 219 × 96。
///
/// 圆角 16 点，内边距 14 点，底色按种类给。
/// 编辑模式里右上角一个删除钮、右下角一个缩放手柄、左下角一个尺寸标签。
struct BentoWidgetCard: View {
    let spot: BentoSpot
    let title: String
    let detail: String
    let tint: ContractColor
    let isEditing: Bool
    /// 正在被拖。拖动中抬阴影并描一圈主色边。
    let isDragging: Bool
    let language: AppLanguage
    let onMoveDirection: (BentoMoveDirection) -> Void
    let onDelete: () -> Void
    let onResize: (CGSize) -> Void
    /// 缩放手势松手。`BentoGrid` 用它忘掉起点档位。
    let onResizeEnded: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: MacTheme.space1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(HubMetrics.bentoCardPadding)

            if isEditing {
                deleteButton
                resizeHandle
                sizeLabel
            }
        }
        .frame(width: width, height: height)
        // 色值乘一个透明度，露出底下的玻璃模糊。控制中心的彩色模块也是透的。
        .background(MacTheme.color(tint).opacity(MacTheme.tintedCardOpacity), in: shape)
        .glassSurface(cornerRadius: HubMetrics.bentoCardRadius)
        .overlay(shape.strokeBorder(isDragging ? MacTheme.accent : .clear, lineWidth: 2))
        .shadow(color: .black.opacity(isDragging ? 0.24 : 0), radius: isDragging ? 14 : 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
        .accessibilityActions {
            if isEditing {
                Button(ContractCopy.copyHubWidgetMoveLeft.text(for: language)) {
                    onMoveDirection(.left)
                }
                Button(ContractCopy.copyHubWidgetMoveRight.text(for: language)) {
                    onMoveDirection(.right)
                }
                Button(ContractCopy.copyHubWidgetMoveUp.text(for: language)) {
                    onMoveDirection(.up)
                }
                Button(ContractCopy.copyHubWidgetMoveDown.text(for: language)) {
                    onMoveDirection(.down)
                }
            }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: HubMetrics.bentoCardRadius, style: .continuous)
    }

    /// 卡片宽度按档位跨列，列与列之间的间距也算进来。
    private var width: CGFloat { HubMetrics.bentoCardWidth(columns: spot.size.gridColumns) }
    private var height: CGFloat { HubMetrics.bentoCardHeight(rows: spot.size.gridRows) }

    // MARK: - 编辑模式的三件

    private var deleteButton: some View {
        Button(action: onDelete) {
            Text("✕")
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .frame(width: HubMetrics.bentoDeleteSize, height: HubMetrics.bentoDeleteSize)
                .background(Color.black.opacity(0.4), in: Circle())
                // 合同要求命中区不小于 24 点，圆点只有 20 点，靠外扩的内容形状补齐。
                .contentShape(Circle().inset(by: -2))
        }
        .buttonStyle(.plain)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .accessibilityLabel(ContractCopy.copyHubWidgetRemove.text(for: language))
    }

    private var resizeHandle: some View {
        Text("◢")
            .font(.system(size: 13))
            .foregroundStyle(MacTheme.textSecondary)
            .frame(width: HubMetrics.bentoResizeSize, height: HubMetrics.bentoResizeSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { onResize($0.translation) }
                    .onEnded { _ in onResizeEnded() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .accessibilityLabel(ContractCopy.copyHubWidgetResize.text(for: language))
    }

    private var sizeLabel: some View {
        Text(WidgetCatalog.sizeLabel(spot.size).text(for: language))
            .font(.system(size: 10))
            .foregroundStyle(MacTheme.textSecondary)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)
    }
}
