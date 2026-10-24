package com.wyz.covio.core

/**
 * 应用目录。两个平台给出相同的结果。
 *
 * macOS 的布局：
 * - 配置：`~/Library/Application Support/com.wyz.covio/config.json`
 * - 截图索引：`~/Library/Application Support/Covio/Screenshots/shelf.json`
 *
 * 注意应用数据目录用的是 `APP_NAME`，配置目录用的是 `APP_ID`。两者不同。
 * 这是 0.4.2 的既有布局，不能改，否则老用户的设置会丢。
 *
 * 目录的字面量只在 actual 里出现。common 不写平台路径。
 * 这样接第二个平台时，只改 actual，不动业务代码。
 *
 * 路径用 String 表示。Kotlin/Native 没有 `java.nio.file.Path`，
 * 文件操作统一走 okio 的 `FileSystem`。
 */
internal expect object AppDirectories {
    /** 用户主目录。 */
    val home: String

    /** 用户级应用数据根目录。`support` 是它下面按 `APP_ID` 建的目录。 */
    val userApplicationSupport: String

    /** 配置与日志所在的应用数据目录。 */
    val support: String
}

internal fun defaultConfigPath(): String = "${AppDirectories.support}/config.json"

/**
 * 工作台配置。放在配置目录下，与 `config.json` 并列。
 *
 * 单独一个文件。理由见 [WorkbenchStore]：`config.json` 承诺与 0.4.2 双向兼容，
 * 工作台配置不用背这个包袱；而且坏掉一个文件时另一个还能读。
 */
internal fun defaultWorkbenchPath(): String = "${AppDirectories.support}/workbench.json"

internal fun defaultShelfPath(): String =
    "${AppDirectories.userApplicationSupport}/${APP_NAME}/Screenshots/shelf.json"
