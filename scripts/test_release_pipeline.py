import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("release_pipeline.py")
SPEC = importlib.util.spec_from_file_location("release_pipeline", SCRIPT)
assert SPEC and SPEC.loader
pipeline = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = pipeline
SPEC.loader.exec_module(pipeline)


class ReleasePipelineTests(unittest.TestCase):
    commit = "a" * 40
    helper_hash = "b" * 64

    def setUp(self):
        self.source = pipeline.release.ReleaseSpec(1, "1.2.3", 4, "internal", 8)
        self.artifact = {
            "schemaVersion": 1,
            "releaseId": f"1.2.3+4+{self.commit}",
            "productVersion": "1.2.3",
            "buildNumber": 4,
            "gitCommit": self.commit,
            "helperProtocolVersion": 8,
            "helperSHA256": self.helper_hash,
            "channel": "internal",
        }
        self.app_info = {
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "4",
            "CovioReleaseId": self.artifact["releaseId"],
            "CovioGitCommit": self.commit,
            "CovioHelperProtocolVersion": "8",
            "CovioReleaseChannel": "internal",
        }
        self.helper = {
            "releaseId": self.artifact["releaseId"],
            "productVersion": "1.2.3",
            "buildNumber": "4",
            "gitCommit": self.commit,
            "protocolVersion": "8",
            "helperSHA256": self.helper_hash,
            "channel": "internal",
        }

    def test_matching_identity_has_no_errors(self):
        self.assertEqual(
            pipeline.identity_errors(
                self.source,
                self.artifact,
                self.app_info,
                self.helper,
                self.helper_hash,
            ),
            [],
        )

    def test_release_id_version_protocol_and_hash_mismatches_fail(self):
        cases = [
            (self.artifact | {"releaseId": "wrong"}, {}, {}, self.helper_hash),
            (self.artifact | {"productVersion": "9.9.9"}, {}, {}, self.helper_hash),
            (self.artifact | {"helperProtocolVersion": 9}, {}, {}, self.helper_hash),
            (self.artifact, {}, {}, "c" * 64),
            (self.artifact, {"CFBundleVersion": "5"}, {}, self.helper_hash),
            (self.artifact, {}, {"gitCommit": "d" * 40}, self.helper_hash),
        ]
        for artifact, app_override, helper_override, actual_hash in cases:
            app = self.app_info | app_override
            helper = self.helper | helper_override
            with self.subTest(artifact=artifact, app=app_override, helper=helper_override):
                self.assertNotEqual(
                    pipeline.identity_errors(
                        self.source,
                        artifact,
                        app,
                        helper,
                        actual_hash,
                    ),
                    [],
                )

    def test_architecture_requires_arm64_for_both_binaries(self):
        self.assertEqual(pipeline.architecture_errors("arm64", "arm64"), [])
        self.assertEqual(len(pipeline.architecture_errors("x86_64", "arm64")), 1)
        self.assertEqual(len(pipeline.architecture_errors("arm64", "x86_64")), 1)

    def test_public_signature_requires_developer_id_runtime_and_installer(self):
        app = "Authority=Developer ID Application: Covio\nTeamIdentifier=TEAM\nflags=0x10000(runtime)"
        dmg = "Authority=Developer ID Application: Covio\nTeamIdentifier=TEAM"
        pkg = "Status: signed\nDeveloper ID Installer: Covio"
        self.assertEqual(pipeline.signature_errors(app, app, pkg, dmg, "public"), [])
        self.assertNotEqual(pipeline.signature_errors("Signature=adhoc", app, pkg, dmg, "public"), [])
        self.assertNotEqual(pipeline.signature_errors(app, app, "Status: unsigned", dmg, "public"), [])
        self.assertNotEqual(pipeline.signature_errors(app.replace("(runtime)", ""), app, pkg, dmg, "public"), [])
        self.assertNotEqual(pipeline.signature_errors(app, app, pkg, "Signature=adhoc", "public"), [])

    def test_internal_signature_does_not_require_developer_id(self):
        self.assertEqual(
            pipeline.signature_errors("Signature=adhoc", "Signature=adhoc", "", "", "internal"),
            [],
        )

    def test_public_notarization_requires_every_ticket_and_gatekeeper_check(self):
        ok = pipeline.CommandResult(0, "accepted")
        failed = pipeline.CommandResult(1, "rejected")
        self.assertEqual(
            pipeline.notarization_errors("public", ok, ok, ok, ok, ok),
            [],
        )
        errors = pipeline.notarization_errors("public", ok, failed, ok, ok, ok)
        self.assertEqual(len(errors), 1)
        self.assertIn("dmg staple", errors[0])

    def test_checksums_are_deterministic_and_detect_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for name in (*pipeline.expected_asset_names("1.2.3"), "release-manifest.json"):
                (root / name).write_bytes(name.encode("utf-8"))
            first = pipeline.write_checksums(root, "1.2.3").read_text(encoding="utf-8")
            second = pipeline.write_checksums(root, "1.2.3").read_text(encoding="utf-8")
            self.assertEqual(first, second)
            pipeline.verify_checksums(root, "1.2.3")
            (root / "Covio-1.2.3.dmg").write_bytes(b"changed")
            with self.assertRaises(pipeline.ReleaseVerificationError):
                pipeline.verify_checksums(root, "1.2.3")

    def test_checksum_asset_set_is_complete(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for name in (*pipeline.expected_asset_names("1.2.3"), "release-manifest.json"):
                (root / name).write_bytes(name.encode("utf-8"))
            pipeline.write_checksums(root, "1.2.3")
            (root / "Covio-1.2.3.pkg").unlink()
            with self.assertRaises(pipeline.ReleaseVerificationError):
                pipeline.verify_checksums(root, "1.2.3")

    def test_internal_and_public_tags_are_distinct(self):
        public = self.source.__class__(1, "1.2.3", 4, "public", 8)
        self.assertEqual(pipeline.release_tag(self.source), "v1.2.3-internal.4")
        self.assertEqual(pipeline.release_tag(public), "v1.2.3")

    def test_internal_release_never_becomes_latest(self):
        internal = pipeline.public_visibility("internal")
        public = pipeline.public_visibility("public")
        self.assertFalse(internal["isLatest"])
        self.assertTrue(internal["isPrerelease"])
        self.assertTrue(public["isLatest"])
        self.assertFalse(public["isPrerelease"])

    def test_promotion_requires_draft_and_paired_assets(self):
        evidence = {
            "tag": "v1.2.3-internal.4",
            "productVersion": "1.2.3",
            "assets": {
                name: {"sha256": "a" * 64, "size": 1}
                for name in pipeline.expected_asset_names("1.2.3")
            },
        }
        info = {"isDraft": True, "isPrerelease": True, "tagName": evidence["tag"]}
        self.assertEqual(pipeline.promotion_errors("internal", info, evidence), [])
        self.assertNotEqual(
            pipeline.promotion_errors("internal", info | {"isDraft": False}, evidence),
            [],
        )
        incomplete = evidence | {"assets": {"Covio-1.2.3.dmg": {"sha256": "a" * 64, "size": 1}}}
        self.assertNotEqual(pipeline.promotion_errors("internal", info, incomplete), [])

    def test_release_notes_include_release_evidence_and_hashes(self):
        evidence = {
            "channel": "internal",
            "releaseId": f"1.2.3+4+{self.commit}",
            "productVersion": "1.2.3",
            "buildNumber": 4,
            "gitCommit": self.commit,
            "helperProtocolVersion": 8,
            "helperSHA256": self.helper_hash,
            "tag": "v1.2.3-internal.4",
            "assets": {
                "Covio-1.2.3.dmg": {"sha256": "c" * 64, "size": 123},
            },
            "verification": {
                "identity": "MATCH",
                "signatureKind": "adhoc",
                "notarized": False,
            },
        }
        notes = pipeline.render_notes(evidence, "# Notes")
        self.assertIn(evidence["releaseId"], notes)
        self.assertIn("c" * 64, notes)
        self.assertIn("# Notes", notes)


if __name__ == "__main__":
    unittest.main()
