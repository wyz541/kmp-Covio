package com.wyz.covio.app.ui

import com.wyz.covio.core.AppConfig
import com.wyz.covio.core.AppState
import com.wyz.covio.core.BatteryStatus
import com.wyz.covio.core.HelperStatus
import com.wyz.covio.core.PowerState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TrayPresentationTest {
    @Test
    fun `icon state follows the approved priority`() {
        val unavailable = AppState(
            battery = BatteryStatus(2, PowerState.DISCHARGING, 60),
            idleSleepAvailable = false,
            lidSleepAvailable = false,
        )
        assertEquals(
            TrayIconState.HELPER_ERROR,
            resolveTrayIconState(AppConfig(enabled = false), unavailable, HelperStatus.MISSING),
        )
        assertEquals(
            TrayIconState.DISABLED,
            resolveTrayIconState(AppConfig(enabled = false), unavailable, HelperStatus.MATCH),
        )
        assertEquals(
            TrayIconState.LOW_BATTERY,
            resolveTrayIconState(AppConfig(lowBatteryCapacity = 20), unavailable, HelperStatus.MATCH),
        )
        assertEquals(
            TrayIconState.CHARGING,
            resolveTrayIconState(
                AppConfig(),
                AppState(
                    battery = BatteryStatus(20, PowerState.CHARGING, null),
                    idleSleepAvailable = false,
                    lidSleepAvailable = false,
                ),
                HelperStatus.MATCH,
            ),
        )
        assertEquals(
            TrayIconState.LID_PREVENTION,
            resolveTrayIconState(
                AppConfig(),
                AppState(idleSleepAvailable = false, lidSleepAvailable = false),
                HelperStatus.MATCH,
            ),
        )
        assertEquals(
            TrayIconState.IDLE_PREVENTION,
            resolveTrayIconState(
                AppConfig(),
                AppState(idleSleepAvailable = false, lidSleepAvailable = true),
                HelperStatus.MATCH,
            ),
        )
        assertEquals(
            TrayIconState.DEFAULT,
            resolveTrayIconState(AppConfig(), AppState(), HelperStatus.MATCH),
        )
    }

    @Test
    fun `low battery uses inclusive capacity and time boundaries`() {
        val capacityBoundary = AppState(
            battery = BatteryStatus(6, PowerState.DISCHARGING, 7_200),
        )
        val timeBoundary = AppState(
            battery = BatteryStatus(80, PowerState.DISCHARGING, 600),
        )
        val charging = AppState(
            battery = BatteryStatus(1, PowerState.CHARGING, 60),
        )

        assertEquals(
            TrayIconState.LOW_BATTERY,
            resolveTrayIconState(AppConfig(lowBatteryCapacity = 6), capacityBoundary, HelperStatus.MATCH),
        )
        assertEquals(
            TrayIconState.LOW_BATTERY,
            resolveTrayIconState(AppConfig(lowTimeRemainingMinutes = 10), timeBoundary, HelperStatus.MATCH),
        )
        assertEquals(
            TrayIconState.DEFAULT,
            resolveTrayIconState(AppConfig(lowBatteryCapacity = 0), capacityBoundary, HelperStatus.MATCH),
        )
        assertEquals(
            TrayIconState.CHARGING,
            resolveTrayIconState(AppConfig(lowBatteryCapacity = 50), charging, HelperStatus.MATCH),
        )
    }

    @Test
    fun `tray presentation contains bilingual status and dynamic tooltip`() {
        val config = AppConfig(lowBatteryCapacity = 20)
        val state = AppState(
            battery = BatteryStatus(12, PowerState.DISCHARGING, 900),
            idleSleepAvailable = false,
            lidSleepAvailable = false,
        )
        val english = resolveTrayPresentation(
            config,
            state,
            HelperStatus.MATCH,
            stringsFor(AppLanguage.ENGLISH),
            AppLanguage.ENGLISH,
        )
        val chinese = resolveTrayPresentation(
            config,
            state,
            HelperStatus.MATCH,
            stringsFor(AppLanguage.SIMPLIFIED_CHINESE),
            AppLanguage.SIMPLIFIED_CHINESE,
        )

        assertEquals(TrayIconState.LOW_BATTERY, english.iconState)
        assertEquals("Low Battery", english.statusLabel)
        assertTrue(english.tooltip.contains("Battery: 12% · On battery"), english.tooltip)
        assertTrue(english.tooltip.contains("Idle prevention: On"), english.tooltip)
        assertTrue(english.tooltip.contains("Lid prevention: On"), english.tooltip)
        assertEquals("低电量", chinese.statusLabel)
        assertTrue(chinese.tooltip.contains("闲置阻止：开启"), chinese.tooltip)
        assertTrue(chinese.tooltip.contains("合盖阻止：开启"), chinese.tooltip)
    }

    @Test
    fun `tray menu structure keeps the approved order`() {
        assertEquals(
            listOf(
                TrayMenuSection.STATUS,
                TrayMenuSection.PRIMARY,
                TrayMenuSection.SLEEP_RULES,
                TrayMenuSection.TOP_SHELF,
                TrayMenuSection.SETTINGS,
                TrayMenuSection.MORE,
                TrayMenuSection.APPLICATION,
            ),
            TRAY_MENU_STRUCTURE.map { it.section },
        )
        assertEquals(
            listOf(
                TrayMenuItemId.STATUS_TITLE,
                TrayMenuItemId.BATTERY,
                TrayMenuItemId.ENABLED,
                TrayMenuItemId.SLEEP_NOW,
                TrayMenuItemId.TURN_DISPLAY_OFF,
                TrayMenuItemId.SLEEP_RULES,
                TrayMenuItemId.TOP_SHELF,
                TrayMenuItemId.SETTINGS,
                TrayMenuItemId.MORE,
                TrayMenuItemId.ABOUT,
                TrayMenuItemId.QUIT,
            ),
            TRAY_MENU_STRUCTURE.flatMap { it.items }.filter {
                it in setOf(
                    TrayMenuItemId.STATUS_TITLE,
                    TrayMenuItemId.BATTERY,
                    TrayMenuItemId.ENABLED,
                    TrayMenuItemId.SLEEP_NOW,
                    TrayMenuItemId.TURN_DISPLAY_OFF,
                    TrayMenuItemId.SLEEP_RULES,
                    TrayMenuItemId.TOP_SHELF,
                    TrayMenuItemId.SETTINGS,
                    TrayMenuItemId.MORE,
                    TrayMenuItemId.ABOUT,
                    TrayMenuItemId.QUIT,
                )
            },
        )
    }
}
