package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HelperReleaseIdentityTest {
    private val commit = "a".repeat(40)
    private val hash = "b".repeat(64)
    private val expected = identity()

    @Test
    fun `complete wire fields parse to the canonical identity`() {
        assertEquals(expected, HelperReleaseHandshake.parse(wire(expected)))
    }

    @Test
    fun `version reply carries both legacy fields and the complete identity`() {
        val reply = HelperWire.versionReply("r", expected)

        assertEquals(expected.productVersion, reply.result?.get("version"))
        assertEquals(expected.productVersion, reply.result?.get("productVersion"))
        assertEquals(expected, HelperReleaseHandshake.parse(reply.result.orEmpty()))
    }

    @Test
    fun `legacy reply has no identity fields`() {
        val legacy = mapOf("version" to "0.5.1", "protocolVersion" to "8")

        assertNull(HelperReleaseHandshake.parse(legacy))
        assertFalse(HelperReleaseHandshake.hasIdentityFields(legacy))
    }

    @Test
    fun `partial or malformed identity is untrusted`() {
        val partial = wire(expected) - "helperSHA256"
        val malformed = wire(expected) + ("releaseId" to "not-a-release-id")

        assertNull(HelperReleaseHandshake.parse(partial))
        assertTrue(HelperReleaseHandshake.hasIdentityFields(partial))
        assertNull(HelperReleaseHandshake.parse(malformed))
    }

    @Test
    fun `exact identity and trusted signature match`() {
        assertEquals(
            HelperStatus.MATCH,
            HelperReleaseHandshake.classify(expected, expected, signatureTrusted = true),
        )
    }

    @Test
    fun `older helper or protocol is outdated`() {
        val olderVersion = expected.copy(
            releaseId = "0.5.1+1+$commit",
            productVersion = "0.5.1",
        )
        val olderBuild = expected.copy(
            releaseId = "0.5.2+0+$commit",
            buildNumber = "0",
        )
        val differentProtocol = expected.copy(protocolVersion = "7")

        assertEquals(
            HelperStatus.OUTDATED,
            HelperReleaseHandshake.classify(expected, olderVersion, signatureTrusted = true),
        )
        assertEquals(
            HelperStatus.OUTDATED,
            HelperReleaseHandshake.classify(expected, olderBuild, signatureTrusted = true),
        )
        assertEquals(
            HelperStatus.OUTDATED,
            HelperReleaseHandshake.classify(expected, differentProtocol, signatureTrusted = true),
        )
    }

    @Test
    fun `same version with different commit or helper digest mismatches`() {
        val differentCommit = expected.copy(
            releaseId = "0.5.2+1+${"c".repeat(40)}",
            gitCommit = "c".repeat(40),
        )
        val differentHash = expected.copy(helperSHA256 = "d".repeat(64))

        assertEquals(
            HelperStatus.IDENTITY_MISMATCH,
            HelperReleaseHandshake.classify(expected, differentCommit, signatureTrusted = true),
        )
        assertEquals(
            HelperStatus.IDENTITY_MISMATCH,
            HelperReleaseHandshake.classify(expected, differentHash, signatureTrusted = true),
        )
    }

    @Test
    fun `untrusted signature wins over identity equality`() {
        assertEquals(
            HelperStatus.UNTRUSTED,
            HelperReleaseHandshake.classify(expected, expected, signatureTrusted = false),
        )
    }

    @Test
    fun `only match allows privileged writes`() {
        assertTrue(HelperStatus.MATCH.allowsPrivilegedWrites)
        listOf(
            HelperStatus.MISSING,
            HelperStatus.OUTDATED,
            HelperStatus.IDENTITY_MISMATCH,
            HelperStatus.UNTRUSTED,
        ).forEach { status ->
            assertFalse(status.allowsPrivilegedWrites, status.name)
        }
    }

    private fun identity() = HelperReleaseIdentity(
        releaseId = "0.5.2+1+$commit",
        productVersion = "0.5.2",
        buildNumber = "1",
        gitCommit = commit,
        protocolVersion = "8",
        helperSHA256 = hash,
        channel = "internal",
    )

    private fun wire(identity: HelperReleaseIdentity): Map<String, String> = mapOf(
        "version" to identity.productVersion,
        "releaseId" to identity.releaseId,
        "productVersion" to identity.productVersion,
        "buildNumber" to identity.buildNumber,
        "gitCommit" to identity.gitCommit,
        "protocolVersion" to identity.protocolVersion,
        "helperSHA256" to identity.helperSHA256,
        "channel" to identity.channel,
    )
}
