package com.wyz.covio.app

import com.wyz.covio.app.helper.HelperInstaller
import com.wyz.covio.app.helper.HelperProtocol
import com.wyz.covio.core.HELPER_BINARY_PATH
import com.wyz.covio.core.HELPER_XPC_SERVICE_NAME
import kotlin.test.Test
import kotlin.test.assertTrue

class HelperInstallerTest {
    private val executablePath = "/Applications/Covio.app/Contents/MacOS/CovioHelper"
    private val script = HelperInstaller.installScript(executablePath, uid = "501")

    @Test
    fun `install script locks the helper directory to root`() {
        assertTrue(script.contains("chown root:wheel '${HelperProtocol.HELPER_DIRECTORY}'"))
        assertTrue(script.contains("chmod 0755 '${HelperProtocol.HELPER_DIRECTORY}'"))
    }

    @Test
    fun `install script makes allowed uid read only for the user`() {
        assertTrue(
            script.contains(
                "chmod 0644 '${HelperProtocol.ALLOWED_UID_PATH}' '${HelperProtocol.VERSION_PATH}' '${HelperProtocol.APP_PATH_FILE}'",
            ),
        )
        assertTrue(script.contains("printf '%s\\n' '501' > '${HelperProtocol.ALLOWED_UID_PATH}'"))
    }

    @Test
    fun `install script copies the helper to the fixed path`() {
        assertTrue(script.contains("/usr/bin/ditto '$executablePath' '$HELPER_BINARY_PATH.new'"))
        assertTrue(script.contains("mv '$HELPER_BINARY_PATH.new' '$HELPER_BINARY_PATH'"))
    }

    @Test
    fun `install script writes the launch daemon plist`() {
        assertTrue(script.contains("${HelperProtocol.PLIST_PATH}.new"))
        assertTrue(script.contains("mv '${HelperProtocol.PLIST_PATH}.new' '${HelperProtocol.PLIST_PATH}'"))
        assertTrue(script.contains("<string>$HELPER_BINARY_PATH</string>"))
        assertTrue(script.contains("<key>$HELPER_XPC_SERVICE_NAME</key>"))
    }
}
