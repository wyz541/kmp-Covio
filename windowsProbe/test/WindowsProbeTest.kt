package com.wyz.covio.windows

import com.wyz.covio.core.APP_VERSION
import kotlin.test.Test
import kotlin.test.assertTrue

class WindowsProbeTest {
    @Test
    fun sharedDomainIsAvailable() {
        assertTrue(APP_VERSION.isNotBlank())
    }
}
