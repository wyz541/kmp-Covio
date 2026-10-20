package com.wyz.covio.app.helper

import com.wyz.covio.core.HelperReply
import com.wyz.covio.core.HelperRequest
import java.io.ByteArrayOutputStream
import java.net.SocketTimeoutException
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.SelectionKey
import java.nio.channels.Selector
import java.nio.channels.SocketChannel
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID

class HelperClient(
    private val socketPath: Path = Path.of(HelperProtocol.SOCKET_PATH),
) {
    fun request(
        command: String,
        payload: Map<String, String> = emptyMap(),
        timeoutMillis: Int = 2_000,
        protocolVersion: String = HelperProtocol.PROTOCOL_VERSION,
    ): HelperReply? {
        if (!Files.exists(socketPath) || timeoutMillis <= 0) return null
        return runCatching {
            val deadline = System.nanoTime() + timeoutMillis.toLong() * 1_000_000L
            SocketChannel.open(StandardProtocolFamily.UNIX).use { channel ->
                channel.configureBlocking(false)
                Selector.open().use { selector ->
                    val key = channel.register(selector, SelectionKey.OP_CONNECT)
                    if (!channel.connect(UnixDomainSocketAddress.of(socketPath))) {
                        await(selector, key, SelectionKey.OP_CONNECT, deadline)
                        channel.finishConnect()
                    }

                    val line = HelperProtocol.encodeRequest(
                        HelperRequest(
                            version = protocolVersion,
                            requestId = UUID.randomUUID().toString(),
                            command = command,
                            payload = payload,
                        ),
                    ) + "\n"
                    writeAll(channel, selector, key, line.toByteArray(StandardCharsets.UTF_8), deadline)
                    readReply(channel, selector, key, deadline)
                }
            }
        }.getOrNull()
    }

    /// 用 v1 探测旧 helper。新版 helper 保留这一条只读兼容路径。
    fun version(): String? = request("version", protocolVersion = "1")
        ?.takeIf { it.ok }
        ?.result
        ?.get("version")

    fun acquireLidLease(leaseId: String, externalDisplayCount: Int): HelperReply? =
        request(
            "lidLeaseAcquire",
            mapOf(
                "leaseId" to leaseId,
                "externalDisplayCount" to externalDisplayCount.toString(),
            ),
        )

    fun renewLidLease(leaseId: String, externalDisplayCount: Int): HelperReply? =
        request(
            "lidLeaseRenew",
            mapOf(
                "leaseId" to leaseId,
                "externalDisplayCount" to externalDisplayCount.toString(),
            ),
        )

    fun releaseLidLease(leaseId: String): HelperReply? =
        request("lidLeaseRelease", mapOf("leaseId" to leaseId))

    fun lidLeaseStatus(): HelperReply? = request("lidLeaseStatus")

    fun setHibernateMode(mode: Int): Boolean =
        request("setHibernateMode", mapOf("mode" to mode.toString()))?.ok == true

    private fun writeAll(
        channel: SocketChannel,
        selector: Selector,
        key: SelectionKey,
        bytes: ByteArray,
        deadline: Long,
    ) {
        val buffer = ByteBuffer.wrap(bytes)
        while (buffer.hasRemaining()) {
            if (channel.write(buffer) == 0) {
                await(selector, key, SelectionKey.OP_WRITE, deadline)
            }
        }
    }

    private fun readReply(
        channel: SocketChannel,
        selector: Selector,
        key: SelectionKey,
        deadline: Long,
    ): HelperReply? {
        val output = ByteArrayOutputStream()
        val buffer = ByteBuffer.allocate(4_096)
        while (output.size() < MAX_REPLY_BYTES) {
            buffer.clear()
            val count = channel.read(buffer)
            if (count < 0) break
            if (count == 0) {
                await(selector, key, SelectionKey.OP_READ, deadline)
                continue
            }
            val chunk = ByteArray(count)
            buffer.flip()
            buffer.get(chunk)
            output.write(chunk)
            if (chunk.any { it == '\n'.code.toByte() }) break
        }
        if (output.size() >= MAX_REPLY_BYTES) throw SocketTimeoutException("Helper reply is too large")
        val response = output.toString(StandardCharsets.UTF_8.name()).substringBefore('\n')
        return HelperProtocol.decodeReply(response)
    }

    private fun await(selector: Selector, key: SelectionKey, operation: Int, deadline: Long) {
        key.interestOps(operation)
        while (true) {
            val remaining = deadline - System.nanoTime()
            if (remaining <= 0L) throw SocketTimeoutException("Helper request timed out")
            val millis = ((remaining + 999_999L) / 1_000_000L).coerceAtLeast(1L)
            if (selector.select(millis) == 0) throw SocketTimeoutException("Helper request timed out")
            val selected = selector.selectedKeys()
            val iterator = selected.iterator()
            while (iterator.hasNext()) {
                val ready = iterator.next()
                iterator.remove()
                if (ready == key && ready.isValid && ready.readyOps() and operation != 0) return
            }
        }
    }

    companion object {
        private const val MAX_REPLY_BYTES = 64 * 1024
    }
}
