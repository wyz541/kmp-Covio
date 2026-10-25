import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("release_manifest.py")
SPEC = importlib.util.spec_from_file_location("release_manifest", SCRIPT)
assert SPEC and SPEC.loader
release = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = release
SPEC.loader.exec_module(release)


class ReleaseManifestTests(unittest.TestCase):
    def test_release_id_is_deterministic(self):
        spec = release.ReleaseSpec(1, "1.2.3", 4, "internal", 8)
        commit = "a" * 40
        self.assertEqual(release.release_id(spec, commit), f"1.2.3+4+{commit}")
        self.assertEqual(release.release_id(spec, commit), release.release_id(spec, commit))

    def test_bump_increments_build_and_can_change_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / release.SOURCE_MANIFEST).parent.mkdir(parents=True)
            (root / release.SOURCE_MANIFEST).write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "productVersion": "1.2.3",
                        "buildNumber": 4,
                        "channel": "internal",
                        "helperProtocolVersion": 8,
                    }
                ),
                encoding="utf-8",
            )
            (root / release.HELPER_CONTRACT).parent.mkdir(parents=True)
            (root / release.HELPER_CONTRACT).write_text(
                'const val HELPER_PROTOCOL_VERSION = "8"\n', encoding="utf-8"
            )
            (root / release.SIGNING_XCCONFIG).parent.mkdir(parents=True)
            (root / release.SIGNING_XCCONFIG).write_text(
                '#include "ReleaseIdentity.generated.xcconfig"\n', encoding="utf-8"
            )
            (root / release.INFO_PLIST).parent.mkdir(parents=True)
            (root / release.INFO_PLIST).write_text(
                "".join(
                    f"<key>{key}</key>\n" for key in (
                        "CFBundleVersion",
                        "CovioReleaseChannel",
                        "CovioGitCommit",
                        "CovioReleaseId",
                        "CovioHelperProtocolVersion",
                    )
                )
                + "<string>$(CURRENT_PROJECT_VERSION)</string>\n"
                + "<key>CovioInstallTransactionVersion</key>\n<string>1</string>\n",
                encoding="utf-8",
            )
            (root / release.PBXPROJ).parent.mkdir(parents=True)
            (root / release.PBXPROJ).write_text("// clean\n", encoding="utf-8")

            spec = release.bump_build(root, "2.0.0")

            self.assertEqual(spec.product_version, "2.0.0")
            self.assertEqual(spec.build_number, 5)
            self.assertEqual(release.load_spec(root), spec)
            self.assertEqual(release.drift_errors(root), [])

    def test_drift_detects_stale_generated_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_fixture(root)
            path = root / release.KOTLIN_OUT
            path.write_text("stale\n", encoding="utf-8")
            self.assertIn(
                f"generated file is stale: {release.KOTLIN_OUT}",
                release.drift_errors(root),
            )

    def test_artifact_manifest_rejects_helper_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_fixture(root)
            helper = root / "helper"
            helper.write_bytes(b"helper-v1")
            spec = release.load_spec(root)
            manifest = release.artifact_manifest(spec, "b" * 40, helper)
            manifest_path = root / "release-manifest.json"
            release._write_json(manifest_path, manifest)
            release.verify_artifact(manifest_path, helper, root)
            helper.write_bytes(b"helper-v2")
            with self.assertRaises(release.ManifestError):
                release.verify_artifact(manifest_path, helper, root)

    def test_artifact_manifest_contains_release_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self._write_fixture(root)
            helper = root / "helper"
            helper.write_bytes(b"helper")
            manifest = release.artifact_manifest(release.load_spec(root), "c" * 40, helper)
            self.assertEqual(manifest["releaseId"], f"1.2.3+4+{'c' * 40}")
            self.assertEqual(manifest["helperSHA256"], release.sha256_file(helper))

    def test_clean_worktree_is_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "tracked.txt").write_text("dirty\n", encoding="utf-8")
            with self.assertRaises(release.ManifestError):
                release.ensure_clean(root)
            subprocess.run(["git", "-C", str(root), "add", "tracked.txt"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(root),
                    "-c",
                    "user.name=Test",
                    "-c",
                    "user.email=test@example.invalid",
                    "commit",
                    "-qm",
                    "fixture",
                ],
                check=True,
            )
            release.ensure_clean(root)

    def _write_fixture(self, root: pathlib.Path):
        (root / release.SOURCE_MANIFEST).parent.mkdir(parents=True)
        (root / release.SOURCE_MANIFEST).write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "productVersion": "1.2.3",
                    "buildNumber": 4,
                    "channel": "internal",
                    "helperProtocolVersion": 8,
                }
            ),
            encoding="utf-8",
        )
        (root / release.HELPER_CONTRACT).parent.mkdir(parents=True)
        (root / release.HELPER_CONTRACT).write_text(
            'const val HELPER_PROTOCOL_VERSION = "8"\n', encoding="utf-8"
        )
        (root / release.SIGNING_XCCONFIG).parent.mkdir(parents=True)
        (root / release.SIGNING_XCCONFIG).write_text(
            '#include "ReleaseIdentity.generated.xcconfig"\n', encoding="utf-8"
        )
        (root / release.INFO_PLIST).parent.mkdir(parents=True)
        (root / release.INFO_PLIST).write_text(
            "".join(
                f"<key>{key}</key>\n" for key in (
                    "CFBundleVersion",
                    "CovioReleaseChannel",
                    "CovioGitCommit",
                    "CovioReleaseId",
                    "CovioHelperProtocolVersion",
                )
            )
            + "<string>$(CURRENT_PROJECT_VERSION)</string>\n"
            + "<key>CovioInstallTransactionVersion</key>\n<string>1</string>\n",
            encoding="utf-8",
        )
        (root / release.PBXPROJ).parent.mkdir(parents=True)
        (root / release.PBXPROJ).write_text("// clean\n", encoding="utf-8")
        release.write_generated(root)


if __name__ == "__main__":
    unittest.main()
