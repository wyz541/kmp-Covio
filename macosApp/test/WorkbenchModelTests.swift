import XCTest
import kmpDomain
@testable import Covio

/// 工作台模型：目的地、页签、首页组件与编辑模式。
///
/// 这些断言守着的是「视图读到的值与配置一致」。模型错了的后果是界面显示
/// 一个用户没存过的状态，而落盘的那一份还是旧的。
@MainActor
final class WorkbenchModelTests: XCTestCase {
    private func model() -> WorkbenchModel {
        WorkbenchModel()
    }

    // MARK: - 初始状态

    /// 初始停在首页，不在编辑模式。
    func testTheModelStartsOnTheHomePage() {
        let model = model()
        XCTAssertEqual(model.destination, .home)
        XCTAssertFalse(model.isEditing)
    }

    /// 默认配置里有六块组件，与打样一致。
    func testTheDefaultConfigHasSixWidgets() {
        XCTAssertEqual(model().homeWidgets.count, 6)
    }

    /// 默认配置里的内置工作区是六个。`board` 是用户自建的，不在默认里。
    func testTheDefaultConfigShowsEveryBuiltInPane() {
        let model = model()
        XCTAssertEqual(model.panes.count, 6)
        XCTAssertEqual(
            model.panes.map(\.tab),
            [.now, .agent, .clipboard, .files, .devices, .settings]
        )
        for pane in model.panes {
            XCTAssertFalse(pane.title.isEmpty, "\(pane.id) 没有标题")
            XCTAssertFalse(pane.glyph.isEmpty, "\(pane.id) 没有图标")
        }
    }

    /// 首页的行数由装箱算出来，不是写死的。
    func testHomeRowsComeFromThePacker() {
        let model = model()
        XCTAssertEqual(
            model.homeRows,
            BentoPacker.rows(BentoPacker.pack(model.homeWidgets, columns: HubMetrics.bentoColumns))
        )
        XCTAssertGreaterThan(model.homeRows, 0)
    }

    // MARK: - 换页

    /// 选中一个工作区就换到那一页。
    func testSelectingAPaneChangesTheDestination() {
        let model = model()
        model.select(paneID: PaneKind.clipboard.defaultId)
        XCTAssertEqual(model.destination, .pane(id: PaneKind.clipboard.defaultId))
        XCTAssertEqual(model.tab(for: model.destination), .clipboard)
    }

    /// 找不到的工作区停在原地，不崩也不换页。
    func testSelectingAnUnknownPaneDoesNothing() {
        let model = model()
        model.select(paneID: "no-such-pane")
        XCTAssertNotEqual(model.destination, .pane(id: "no-such-pane"))
    }

    /// 旧截图入口进入文件区，并携带一次截图筛选。消费后不重复套用。
    func testTheLegacyScreenshotEntryOpensFilesWithAScreenshotFilter() {
        let model = model()
        model.showFileArea(filter: .screenshots)

        XCTAssertEqual(model.destination, .pane(id: PaneKind.files.defaultId))
        XCTAssertEqual(model.pendingFileFilter, .screenshots)

        model.consumeFileFilterRequest()
        XCTAssertNil(model.pendingFileFilter)
    }

    /// 编辑模式里不换页。页签与卡片是两个页面的东西，一起编辑会串。
    func testSelectingAPaneIsIgnoredWhileEditing() {
        let model = model()
        model.isEditing = true
        model.select(paneID: PaneKind.clipboard.defaultId)
        XCTAssertEqual(model.destination, .home)
    }

    /// 换页就退出编辑模式。
    func testChangingThePageLeavesEditingMode() {
        let model = model()
        model.isEditing = true
        model.destination = .pane(id: PaneKind.files.defaultId)
        XCTAssertFalse(model.isEditing)
    }

    // MARK: - 顶栏右端的动作

    /// 首页上是「编辑」，设置页上是「返回」，其余是「设置」，编辑中是「完成」。
    func testThePageActionFollowsTheDestination() {
        let model = model()
        XCTAssertEqual(model.pageAction.text(for: .simplifiedChinese), ContractCopy.copyHubActionEdit.text(for: .simplifiedChinese))

        model.isEditing = true
        XCTAssertEqual(model.pageAction.text(for: .simplifiedChinese), ContractCopy.copyHubActionDone.text(for: .simplifiedChinese))

        model.isEditing = false
        model.destination = .pane(id: PaneKind.settings.defaultId)
        XCTAssertEqual(model.pageAction.text(for: .simplifiedChinese), ContractCopy.copyHubActionBack.text(for: .simplifiedChinese))

        model.destination = .pane(id: PaneKind.files.defaultId)
        XCTAssertEqual(model.pageAction.text(for: .simplifiedChinese), ContractCopy.copyHubActionSettings.text(for: .simplifiedChinese))
    }

    /// 首页上按一次进编辑模式，再按一次出来。
    func testThePageActionTogglesEditingOnTheHomePage() {
        let model = model()
        model.performPageAction()
        XCTAssertTrue(model.isEditing)
        model.performPageAction()
        XCTAssertFalse(model.isEditing)
    }

    /// 别处按一次进设置页，设置页上按一次回首页。
    func testThePageActionGoesToSettingsAndBack() {
        let model = model()
        model.destination = .pane(id: PaneKind.files.defaultId)
        model.performPageAction()
        XCTAssertEqual(model.destination, .pane(id: PaneKind.settings.defaultId))
        model.performPageAction()
        XCTAssertEqual(model.destination, .home)
    }

    // MARK: - 页标题行

    /// 首页没有页标题行。打样的首页直接从网格开始。
    func testTheHomePageHasNoHeading() {
        XCTAssertNil(model().heading(for: .home))
    }

    /// 每个工作区都有标题与说明。
    func testEveryPaneHasAHeading() {
        let model = model()
        for pane in model.panes {
            let heading = model.heading(for: .pane(id: pane.id))
            XCTAssertNotNil(heading, "\(pane.id) 没有页标题")
            XCTAssertFalse(heading?.title.isEmpty ?? true, "\(pane.id) 的标题为空")
            XCTAssertFalse(heading?.summary.isEmpty ?? true, "\(pane.id) 的说明为空")
        }
    }

    // MARK: - 编辑首页

    /// 换位把一块挪到目标位置，其余顺序不变。
    func testMovingAWidgetReordersTheList() {
        let model = model()
        let before = model.homeWidgets.map(\.id)
        model.moveWidget(from: 0, to: 2)
        var expected = before
        let moved = expected.remove(at: 0)
        expected.insert(moved, at: 2)
        XCTAssertEqual(model.homeWidgets.map(\.id), expected)
    }

    /// 越界的换位按打样的做法夹到两端，不崩也不丢组件。
    ///
    /// 打样 `WorkbenchPreview.kt` 的写法是 `list.add(to.coerceIn(0, list.size), moved)`，
    /// 所以拖过头是「放到最后」，不是「忽略」。
    func testMovingAWidgetOutOfRangeClampsToTheEnds() {
        let model = model()
        let count = model.homeWidgets.count

        model.moveWidget(from: 0, to: 99)
        XCTAssertEqual(model.homeWidgets.map(\.id).last, "w-clock")
        XCTAssertEqual(model.homeWidgets.count, count)

        model.moveWidget(from: count - 1, to: -5)
        XCTAssertEqual(model.homeWidgets.map(\.id).first, "w-clock")
        XCTAssertEqual(model.homeWidgets.count, count)
    }

    /// 起点越界时不动。起点越界说明调用方算错了，夹到两端反而会挪错一块。
    func testMovingAWidgetFromOutOfRangeIsIgnored() {
        let model = model()
        let before = model.homeWidgets.map(\.id)
        model.moveWidget(from: 99, to: 0)
        XCTAssertEqual(model.homeWidgets.map(\.id), before)
    }

    /// 缩放只改那一块的档位，别的字段照旧。
    func testResizingAWidgetKeepsItsOtherFields() {
        let model = model()
        let target = model.homeWidgets[0]
        model.resizeWidget(id: target.id, to: .large)
        let after = model.homeWidgets.first { $0.id == target.id }
        XCTAssertEqual(after?.size.key, "large")
        XCTAssertEqual(after?.kind, target.kind)
    }

    /// 删除只删那一块。
    func testRemovingAWidgetDropsOnlyThatOne() {
        let model = model()
        let target = model.homeWidgets[1]
        model.removeWidget(id: target.id)
        XCTAssertEqual(model.homeWidgets.count, 5)
        XCTAssertFalse(model.homeWidgets.contains { $0.id == target.id })
    }

    /// 删空之后首页是空态，行数为零。
    func testRemovingEveryWidgetLeavesAnEmptyHome() {
        let model = model()
        for widget in model.homeWidgets {
            model.removeWidget(id: widget.id)
        }
        XCTAssertTrue(model.homeWidgets.isEmpty)
        XCTAssertEqual(model.homeRows, 0)
    }

    // MARK: - 页签排序

    /// 页签换位按可见列表的下标走，隐藏的工作区不参与。
    func testMovingAPaneReordersTheVisibleTabs() {
        let model = model()
        let before = model.panes.map(\.id)
        model.movePane(from: 0, to: 1)
        var expected = before
        let moved = expected.remove(at: 0)
        expected.insert(moved, at: 1)
        XCTAssertEqual(model.panes.map(\.id), expected)
    }

    /// 越界的页签换位被忽略。
    func testMovingAPaneOutOfRangeIsIgnored() {
        let model = model()
        let before = model.panes.map(\.id)
        model.movePane(from: 0, to: 99)
        model.movePane(from: 99, to: 0)
        XCTAssertEqual(model.panes.map(\.id), before)
    }

    // MARK: - 指针切换页签

    /// 冷却早就走完了，进入就换，没有等待。
    func testHoveringAnotherPaneSwitchesImmediately() {
        let model = model()
        let target = HubDestination.pane(id: PaneKind.clipboard.defaultId)

        model.pointerEntered(target)

        XCTAssertEqual(model.destination, target)
        XCTAssertNil(model.pendingDestination, "立刻换掉了，不该留下待切换")
    }

    /// 停在已经选中的页签上什么都不做。否则滑块会白闪一次。
    func testHoveringTheCurrentPaneDoesNothing() {
        let model = model()
        model.select(paneID: PaneKind.clipboard.defaultId)

        model.pointerEntered(.pane(id: PaneKind.clipboard.defaultId))

        XCTAssertNil(model.pendingDestination, "停在已选中的页签上不该等")
    }

    /// 冷却没走完，第二次切换先等着。
    func testTheCooldownBlocksASecondSwitch() {
        let model = model()
        let first = HubDestination.pane(id: PaneKind.clipboard.defaultId)
        let second = HubDestination.pane(id: PaneKind.files.defaultId)

        model.pointerEntered(first)
        model.pointerEntered(second)

        XCTAssertEqual(model.destination, first, "冷却里不该换第二次")
        XCTAssertEqual(model.pendingDestination, second, "第二次应该排着")
        XCTAssertNotNil(model.lastSwitchAt)
    }

    /// 冷却走完，排着的那一次自己换过去。
    func testTheDeferredSwitchFiresWhenTheCooldownEnds() async {
        let model = model()
        let second = HubDestination.pane(id: PaneKind.files.defaultId)

        model.pointerEntered(.pane(id: PaneKind.clipboard.defaultId))
        model.pointerEntered(second)
        await waitForSwitch(model, to: second)

        XCTAssertEqual(model.destination, second)
        XCTAssertNil(model.pendingDestination, "换完不该还留着")
    }

    /// 没等到冷却走完就离开，排着的那一次取消。
    func testLeavingTheTabCancelsTheDeferredSwitch() async {
        let model = model()
        let first = HubDestination.pane(id: PaneKind.clipboard.defaultId)
        let second = HubDestination.pane(id: PaneKind.files.defaultId)

        model.pointerEntered(first)
        model.pointerEntered(second)
        model.pointerExited(second)

        XCTAssertNil(model.pendingDestination, "离开该页签应该立刻取消")

        await waitOutTheCooldownWindow()
        XCTAssertEqual(model.destination, first, "离开后不该再换页")
    }

    /// 指针从 A 移到 B 时，事件顺序是 `enter(B)` 再到 `exit(A)`。
    /// 那时排着的是 B，`exit(A)` 不该把它清掉。
    func testLeavingAnotherTabKeepsThePendingSwitch() {
        let model = model()
        let first = HubDestination.pane(id: PaneKind.clipboard.defaultId)
        let second = HubDestination.pane(id: PaneKind.files.defaultId)

        model.pointerEntered(first)
        model.pointerEntered(second)
        model.pointerExited(first)

        XCTAssertEqual(model.pendingDestination, second, "exit(旧页签) 不该动新页签的等待")
    }

    /// 冷却里连着进入两个页签，只换到最后停住的那一个。
    func testHoveringASecondTabRearmsTheSwitch() async {
        let model = model()
        let third = HubDestination.pane(id: PaneKind.devices.defaultId)

        model.pointerEntered(.pane(id: PaneKind.clipboard.defaultId))
        model.pointerEntered(.pane(id: PaneKind.files.defaultId))
        model.pointerEntered(third)
        await waitForSwitch(model, to: third)

        XCTAssertEqual(model.destination, third, "应该换到最后停住的那一个")
    }

    /// 冷却里点选别的页签，排着的那一次作废。用户已经用点选改过主意。
    func testClickingCancelsTheDeferredSwitch() async {
        let model = model()
        let deferred = HubDestination.pane(id: PaneKind.files.defaultId)
        let clicked = HubDestination.pane(id: PaneKind.devices.defaultId)

        model.pointerEntered(.pane(id: PaneKind.clipboard.defaultId))
        model.pointerEntered(deferred)
        model.select(paneID: PaneKind.devices.defaultId)

        XCTAssertEqual(model.destination, clicked)
        XCTAssertNil(model.pendingDestination, "点选应该把排着的那一次清掉")

        await waitOutTheCooldownWindow()
        XCTAssertEqual(model.destination, clicked, "点选之后不该被指针抢回去")
    }

    /// 面板收起时取消待切换。收起后 AppKit 不发 `mouseExited`，不取消还会换一次。
    func testCancelHoverSwitchStopsTheDeferredSwitch() async {
        let model = model()
        let first = HubDestination.pane(id: PaneKind.clipboard.defaultId)

        model.pointerEntered(first)
        model.pointerEntered(.pane(id: PaneKind.files.defaultId))
        model.cancelHoverSwitch()

        XCTAssertNil(model.pendingDestination)

        await waitOutTheCooldownWindow()
        XCTAssertEqual(model.destination, first, "取消后不该再换页")
    }

    /// 编辑模式里不换。那时点选也不换页，指针不该是一条后门。
    func testHoveringIsIgnoredWhileEditing() async {
        let model = model()
        model.performPageAction()
        XCTAssertTrue(model.isEditing, "首页上的动作按钮应该进编辑模式")

        model.pointerEntered(.pane(id: PaneKind.clipboard.defaultId))

        XCTAssertNil(model.pendingDestination, "编辑模式里不该换页")

        await waitOutTheCooldownWindow()
        XCTAssertEqual(model.destination, .home, "编辑模式里不该换页")
    }

    /// 首页入口也是一个目的地，指针一样换过去。
    func testHoveringTheHomeEntryGoesBackHome() async {
        let model = model()
        model.select(paneID: PaneKind.clipboard.defaultId)

        model.pointerEntered(.home)
        await waitForSwitch(model, to: .home)

        XCTAssertEqual(model.destination, .home)
    }

    /// 等到换页发生。查状态，不查时长（实测 39）。
    ///
    /// 超时给 4 秒，远大于冷却时长，机器再慢也不至于误报。
    private func waitForSwitch(_ model: WorkbenchModel, to destination: HubDestination) async {
        let deadline = Date().addingTimeInterval(4)
        while model.destination != destination, Date() < deadline {
            // 让出主 actor，计时任务才跑得动。
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// 等一个「不该发生」的有界窗口。冷却时长再加一点余量。
    private func waitOutTheCooldownWindow() async {
        try? await Task.sleep(for: .seconds(HubMotion.hoverCooldown + 0.3))
    }

    // MARK: - 落盘

    /// 接了落盘之后，改动写进文件，重建模型还能读回来。
    func testChangesSurviveAReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-workbench-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let path = directory.appendingPathComponent("workbench.json").path
        let model = model()
        model.attach(store: WorkbenchStore.companion.create(path: path))
        let removed = model.homeWidgets[0].id
        model.removeWidget(id: removed)
        model.movePane(from: 0, to: 1)
        let expectedOrder = model.panes.map(\.id)

        let reloaded = WorkbenchModel()
        reloaded.attach(store: WorkbenchStore.companion.create(path: path))
        XCTAssertFalse(reloaded.homeWidgets.contains { $0.id == removed }, "删除没有落盘")
        XCTAssertEqual(reloaded.panes.map(\.id), expectedOrder, "页签顺序没有落盘")
    }
}
