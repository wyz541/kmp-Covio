package com.wyz.covio.windows

import androidx.compose.material.Text
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import com.wyz.covio.core.APP_VERSION

fun main() = application {
    Window(onCloseRequest = ::exitApplication, title = "Covio") {
        Text("Covio $APP_VERSION on Windows")
    }
}
