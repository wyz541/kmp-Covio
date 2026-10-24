package com.wyz.covio.app.ui

import com.wyz.covio.core.AppConfig
import com.wyz.covio.core.AppState
import com.wyz.covio.core.BatteryStatus
import com.wyz.covio.core.HelperStatus
import com.wyz.covio.core.PowerState

internal enum class TrayIconState {
    HELPER_ERROR,
    DISABLED,
    LOW_BATTERY,
    CHARGING,
    LID_PREVENTION,
    IDLE_PREVENTION,
    DEFAULT,
}

internal data class TrayPresentation(
    val iconState: TrayIconState,
    val statusLabel: String,
    val tooltip: String,
)

internal enum class TrayMenuSection {
    STATUS,
    PRIMARY,
    SLEEP_RULES,
    TOP_SHELF,
    SETTINGS,
    MORE,
    APPLICATION,
}

internal enum class TrayMenuItemId {
    STATUS_TITLE,
    BATTERY,
    ENABLED,
    SLEEP_NOW,
    TURN_DISPLAY_OFF,
    SLEEP_RULES,
    PREVENT_IDLE,
    PREVENT_LID,
    CANCEL_IDLE,
    CANCEL_LID,
    TOP_SHELF,
    SHOW_SHELF,
    CLEAR_SHELF,
    SCREENSHOT_INBOX,
    OPEN_SCREENSHOT_DIRECTORY,
    SHELF_SOUNDS,
    SETTINGS,
    MORE,
    LANGUAGE,
    CHECK_UPDATES,
    SLEEP_MODE,
    INSTALL_HELPER,
    UNINSTALL_HELPER,
    VIEW_LOG,
    EXPORT_LOG,
    CLEAR_CONFIG,
    ABOUT,
    QUIT,
}

internal data class TrayMenuSectionSpec(
    val section: TrayMenuSection,
    val items: List<TrayMenuItemId>,
)

internal val TRAY_MENU_STRUCTURE: List<TrayMenuSectionSpec> = listOf(
    TrayMenuSectionSpec(TrayMenuSection.STATUS, listOf(TrayMenuItemId.STATUS_TITLE, TrayMenuItemId.BATTERY)),
    TrayMenuSectionSpec(TrayMenuSection.PRIMARY, listOf(TrayMenuItemId.ENABLED, TrayMenuItemId.SLEEP_NOW, TrayMenuItemId.TURN_DISPLAY_OFF)),
    TrayMenuSectionSpec(
        TrayMenuSection.SLEEP_RULES,
        listOf(TrayMenuItemId.SLEEP_RULES, TrayMenuItemId.PREVENT_IDLE, TrayMenuItemId.PREVENT_LID, TrayMenuItemId.CANCEL_IDLE, TrayMenuItemId.CANCEL_LID),
    ),
    TrayMenuSectionSpec(
        TrayMenuSection.TOP_SHELF,
        listOf(
            TrayMenuItemId.TOP_SHELF,
            TrayMenuItemId.SHOW_SHELF,
            TrayMenuItemId.CLEAR_SHELF,
            TrayMenuItemId.SCREENSHOT_INBOX,
            TrayMenuItemId.OPEN_SCREENSHOT_DIRECTORY,
            TrayMenuItemId.SHELF_SOUNDS,
        ),
    ),
    TrayMenuSectionSpec(TrayMenuSection.SETTINGS, listOf(TrayMenuItemId.SETTINGS)),
    TrayMenuSectionSpec(
        TrayMenuSection.MORE,
        listOf(
            TrayMenuItemId.MORE,
            TrayMenuItemId.LANGUAGE,
            TrayMenuItemId.CHECK_UPDATES,
            TrayMenuItemId.SLEEP_MODE,
            TrayMenuItemId.INSTALL_HELPER,
            TrayMenuItemId.UNINSTALL_HELPER,
            TrayMenuItemId.VIEW_LOG,
            TrayMenuItemId.EXPORT_LOG,
            TrayMenuItemId.CLEAR_CONFIG,
        ),
    ),
    TrayMenuSectionSpec(TrayMenuSection.APPLICATION, listOf(TrayMenuItemId.ABOUT, TrayMenuItemId.QUIT)),
)

internal data class TrayStrings(
    val ready: String,
    val disabled: String,
    val lowBattery: String,
    val charging: String,
    val lidPrevention: String,
    val idlePrevention: String,
    val helperError: String,
    val battery: String,
    val power: String,
    val idleRule: String,
    val lidRule: String,
    val helper: String,
    val on: String,
    val off: String,
    val unavailable: String,
    val sleepRules: String,
    val more: String,
)

internal fun trayStringsFor(language: AppLanguage): TrayStrings = when (language) {
    AppLanguage.ENGLISH -> TrayStrings(
        ready = "Ready",
        disabled = "Disabled",
        lowBattery = "Low Battery",
        charging = "Charging",
        lidPrevention = "Lid Sleep Prevented",
        idlePrevention = "Idle Sleep Prevented",
        helperError = "Helper Unavailable",
        battery = "Battery",
        power = "Power",
        idleRule = "Idle prevention",
        lidRule = "Lid prevention",
        helper = "Helper",
        on = "On",
        off = "Off",
        unavailable = "Unavailable",
        sleepRules = "Sleep Rules",
        more = "More",
    )

    AppLanguage.SIMPLIFIED_CHINESE -> TrayStrings(
        ready = "就绪",
        disabled = "已停用",
        lowBattery = "低电量",
        charging = "正在充电",
        lidPrevention = "阻止合盖睡眠",
        idlePrevention = "阻止闲置睡眠",
        helperError = "助手不可用",
        battery = "电池",
        power = "电源",
        idleRule = "闲置阻止",
        lidRule = "合盖阻止",
        helper = "助手",
        on = "开启",
        off = "关闭",
        unavailable = "不可用",
        sleepRules = "睡眠规则",
        more = "更多",
    )
}

internal fun resolveTrayIconState(
    config: AppConfig,
    state: AppState,
    helperStatus: HelperStatus,
): TrayIconState {
    if (helperStatus != HelperStatus.MATCH) return TrayIconState.HELPER_ERROR
    if (!config.enabled) return TrayIconState.DISABLED
    if (isLowBattery(config, state)) return TrayIconState.LOW_BATTERY
    if (state.battery?.state?.isCharging == true) return TrayIconState.CHARGING
    if (!state.lidSleepAvailable) return TrayIconState.LID_PREVENTION
    if (!state.idleSleepAvailable) return TrayIconState.IDLE_PREVENTION
    return TrayIconState.DEFAULT
}

internal fun resolveTrayPresentation(
    config: AppConfig,
    state: AppState,
    helperStatus: HelperStatus,
    strings: Strings,
    language: AppLanguage,
): TrayPresentation {
    val labels = trayStringsFor(language)
    val iconState = resolveTrayIconState(config, state, helperStatus)
    val statusLabel = when (iconState) {
        TrayIconState.HELPER_ERROR -> labels.helperError
        TrayIconState.DISABLED -> labels.disabled
        TrayIconState.LOW_BATTERY -> labels.lowBattery
        TrayIconState.CHARGING -> labels.charging
        TrayIconState.LID_PREVENTION -> labels.lidPrevention
        TrayIconState.IDLE_PREVENTION -> labels.idlePrevention
        TrayIconState.DEFAULT -> labels.ready
    }
    val batteryText = state.battery?.let { formatBattery(it, strings) } ?: strings.unknown
    val idleText = if (state.idleSleepAvailable) labels.off else labels.on
    val lidText = when {
        helperStatus != HelperStatus.MATCH -> labels.unavailable
        state.lidSleepAvailable -> labels.off
        else -> labels.on
    }
    val helperText = when (helperStatus) {
        HelperStatus.MATCH -> strings.helperInstalled
        HelperStatus.OUTDATED -> strings.helperOutdated
        HelperStatus.IDENTITY_MISMATCH -> strings.helperOutdated
        HelperStatus.UNTRUSTED -> strings.helperOutdated
        HelperStatus.MISSING -> strings.helperNotInstalled
    }
    val separator = if (language == AppLanguage.SIMPLIFIED_CHINESE) "：" else ": "
    val tooltip = listOf(
        "${labels.battery}$separator$batteryText",
        "${labels.idleRule}$separator$idleText",
        "${labels.lidRule}$separator$lidText",
        helperText,
    ).joinToString("\n")
    return TrayPresentation(iconState = iconState, statusLabel = statusLabel, tooltip = tooltip)
}

private fun isLowBattery(config: AppConfig, state: AppState): Boolean {
    if (!config.lowBatteryCapacitySleep) return false
    val battery = state.battery ?: return false
    if (!battery.isDischarging) return false
    val capacityLow = battery.percent <= config.lowBatteryCapacity
    val remainingLow = battery.remainingSeconds?.let { it <= config.lowTimeRemainingMinutes.toLong() * 60L } == true
    return capacityLow || remainingLow
}

/**
 * 电池状态的一行写法，例如 `82% · 放电`。
 *
 * 放在这里而不是运行时类里：托盘文案是唯一的使用方，
 * 而 Compose 宿主的运行时已经随 M6 退役。
 */
internal fun formatBattery(battery: BatteryStatus, strings: Strings): String {
    val stateText = when (battery.state) {
        PowerState.DISCHARGING -> strings.discharging
        PowerState.CHARGING -> strings.charging
        PowerState.CHARGED -> strings.charged
        PowerState.AC_POWER -> "AC"
        else -> strings.unknown
    }
    return "${battery.percent}% · $stateText"
}
