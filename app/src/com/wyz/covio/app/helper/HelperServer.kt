package com.wyz.covio.app.helper

import com.sun.jna.Library
import com.sun.jna.Memory
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.ptr.IntByReference
import com.wyz.covio.core.HelperReply
import com.wyz.covio.core.HelperWire
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.time.Instant

internal interface PosixLibrary : Library {
    fun socket(domain: Int, type: Int, protocol: Int): Int
    fun bind(socket: Int, address: Pointer, addressLength: Int): Int
    fun listen(socket: Int, backlog: Int): Int
    fun accept(socket: Int, address: Pointer?, addressLength: Pointer?): Int
    fun read(socket: Int, buffer: Pointer, count: Long): Long
    fun write(socket: Int, buffer: Pointer, count: Long): Long
    fun close(fd: Int): Int
    fun unlink(path: String): Int
    fun chmod(path: String, mode: Int): Int
    fun getpeereid(socket: Int, uid: IntByReference, gid: IntByReference): Int
}

object HelperEntrypoint {
    fun run(): Int {
        val logger = HelperLog()
        return try {
            HelperServer(logger).run()
            0
        } catch (error: Throwable) {
            logger.error("Helper failed", error)
            1
        }
    }
}

internal class HelperLog {
    private val path = Path.of(HelperProtocol.LOG_PATH)

    fun info(message: String) = write("INFO", message)
    fun error(message: String, error: Throwable? = null) =
        write("ERROR", message + (error?.let { ": ${it.stackTraceToString()}" } ?: ""))

    @Synchronized
    private fun write(level: String, message: String) {
        runCatching {
            Files.createDirectories(path.parent)
            Files.writeString(
                path,
                "${Instant.now()} $level $message\n",
                StandardCharsets.UTF_8,
                StandardOpenOption.CREATE,
                StandardOpenOption.APPEND,
            )
        }
    }
}

internal class HelperServer(private val logger: HelperLog) {
    private val posix = Native.load("System", PosixLibrary::class.java)
    private var serverSocket = -1

    fun run() {
        val socketPath = File(HelperProtocol.SOCKET_PATH)
        socketPath.parentFile?.mkdirs()
        Files.deleteIfExists(socketPath.toPath())
        serverSocket = posix.socket(AF_UNIX, SOCK_STREAM, 0)
        check(serverSocket >= 0) { "socket() failed" }

        bindServerSocket(HelperProtocol.SOCKET_PATH)
        check(posix.listen(serverSocket, 16) == 0) { "listen() failed" }
        posix.chmod(HelperProtocol.SOCKET_PATH, HelperWire.SOCKET_PERMISSIONS)
        logger.info("Helper listening on ${HelperProtocol.SOCKET_PATH}")

        while (!Thread.currentThread().isInterrupted) {
            val client = posix.accept(serverSocket, null, null)
            if (client < 0) continue
            Thread { handleClient(client) }.apply {
                name = "Covio-helper-client"
                isDaemon = true
                start()
            }
        }
    }

    private fun bindServerSocket(path: String): Unit {
        val bytes = path.toByteArray(StandardCharsets.UTF_8)
        val addressLength = 2 + bytes.size + 1
        val memory = Memory((addressLength + 16).toLong())
        memory.clear()
        memory.setByte(0, (addressLength and 0xFF).toByte())
        memory.setByte(1, AF_UNIX.toByte())
        memory.write(2, bytes, 0, bytes.size)
        check(posix.bind(serverSocket, memory, addressLength) == 0) { "bind() failed" }
    }

    internal fun handleClient(client: Int) {
        try {
            val uid = IntByReference()
            val gid = IntByReference()
            if (posix.getpeereid(client, uid, gid) != 0) {
                writeReply(client, HelperWire.failure("", "Cannot determine peer uid"))
                return
            }
            val allowed = readAllowedUid()
            if (allowed == null || uid.value != allowed) {
                logger.info("Rejected helper request from uid=${uid.value}")
                writeReply(client, HelperWire.failure("", "Peer uid is not allowed"))
                return
            }

            val requestLine = readLine(client) ?: return
            val request = HelperWire.decodeRequest(requestLine)
            if (request == null) {
                writeReply(client, HelperWire.failure("", "Invalid JSON request"))
                return
            }
            val validationError = HelperWire.validate(request)
            if (validationError != null) {
                writeReply(client, HelperWire.failure(request.requestId, validationError))
                return
            }
            val arguments = HelperWire.pmsetArguments(request)
            val reply = if (arguments != null) {
                runPmset(request.requestId, arguments)
            } else if (request.command == HelperWire.COMMAND_VERSION) {
                HelperWire.versionReply(request.requestId)
            } else if (HelperWire.isFanControlCommand(request.command)) {
                // Fan control is implemented by the SwiftUI host. The Compose host
                // answers explicitly instead of running an unsupported command.
                HelperWire.failure(
                    request.requestId,
                    "Fan control is unavailable in the Compose app",
                )
            } else {
                // 白名单外的命令在校验那一步就被拒绝了，这里只是兜底。
                HelperWire.failure(request.requestId, "Command is not allowed")
            }
            writeReply(client, reply)
        } catch (error: Throwable) {
            logger.error("Client request failed", error)
        } finally {
            posix.close(client)
        }
    }

    private fun readAllowedUid(): Int? = runCatching {
        Files.readString(Path.of(HelperProtocol.ALLOWED_UID_PATH)).trim().toInt()
    }.getOrNull()

    /**
     * 跑一条 `pmset` 命令。
     *
     * 参数由共享层给出，退出码的判定也在共享层。
     * 进程启动失败只有本宿主知道原因，所以那一句文案留在本地。
     */
    private fun runPmset(requestId: String, arguments: List<String>) = runCatching {
        val process = ProcessBuilder("/usr/bin/pmset", *arguments.toTypedArray())
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().readText()
        HelperWire.pmsetReply(requestId, process.waitFor(), output)
    }.getOrElse { HelperProtocol.failure(requestId, it.message ?: "pmset failed") }

    private fun readLine(fd: Int): String? {
        val output = StringBuilder()
        val one = Memory(1)
        while (output.length < MAX_REQUEST_BYTES) {
            val count = posix.read(fd, one, 1)
            if (count <= 0L) return output.takeIf { it.isNotEmpty() }?.toString()
            val byte = one.getByte(0).toInt() and 0xFF
            if (byte == '\n'.code) return output.toString()
            output.append(byte.toChar())
        }
        return null
    }

    private fun writeReply(fd: Int, reply: HelperReply) {
        val bytes = (HelperWire.encodeReply(reply) + "\n").toByteArray(StandardCharsets.UTF_8)
        val memory = Memory(bytes.size.toLong())
        memory.write(0, bytes, 0, bytes.size)
        var offset = 0
        while (offset < bytes.size) {
            val count = posix.write(fd, memory.share(offset.toLong()), (bytes.size - offset).toLong())
            if (count <= 0L) return
            offset += count.toInt()
        }
    }

    companion object {
        private const val AF_UNIX = 1
        private const val SOCK_STREAM = 1
        private const val MAX_REQUEST_BYTES = HelperWire.MAX_REQUEST_BYTES
    }
}
