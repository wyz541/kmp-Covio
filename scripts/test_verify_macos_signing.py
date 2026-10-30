import importlib.util
import pathlib
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).with_name("verify_macos_signing.py")
SPEC = importlib.util.spec_from_file_location("verify_macos_signing", SCRIPT)
assert SPEC and SPEC.loader
signing = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = signing
SPEC.loader.exec_module(signing)


AD_HOC_REPORT = """Executable=/tmp/Covio.app/Contents/MacOS/Covio
Identifier=com.wyz.covio
CDHash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
Signature=adhoc
TeamIdentifier=not set
Nested=MacOS/CovioHelper
"""

AD_HOC_REQUIREMENT = """Executable=/tmp/Covio.app/Contents/MacOS/Covio
designated => cdhash H"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
"""

AD_HOC_WITHOUT_REQUIREMENT = """Executable=/tmp/Covio.app/Contents/MacOS/Covio
"""

STABLE_REPORT = """Executable=/tmp/Covio.app/Contents/MacOS/Covio
Identifier=com.wyz.covio
CDHash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
Authority=Covio Dev
TeamIdentifier=not set
Nested=MacOS/CovioHelper
"""

STABLE_REQUIREMENT = """Executable=/tmp/Covio.app/Contents/MacOS/Covio
designated => identifier "com.wyz.covio" and certificate root = H"954adead"
"""

HELPER_REPORT = """Executable=/tmp/Covio.app/Contents/MacOS/CovioHelper
Identifier=com.wyz.covio.helper
CDHash=cccccccccccccccccccccccccccccccccccccccc
Authority=Covio Dev
TeamIdentifier=not set
"""

HELPER_REQUIREMENT = """Executable=/tmp/Covio.app/Contents/MacOS/CovioHelper
designated => identifier "com.wyz.covio.helper" and certificate root = H"954adead"
"""


def identity(
    path=".",
    identifier="com.wyz.covio",
    cdhash="a" * 40,
    requirement='identifier "com.wyz.covio" and certificate root = H"954adead"',
):
    return signing.SigningIdentity(
        path=path,
        identifier=identifier,
        signature="certificate",
        authority="Covio Dev",
        team_identifier=None,
        cdhash=cdhash,
        designated_requirement=requirement,
    )


class VerifyMacOSSigningTests(unittest.TestCase):
    def test_self_signed_identity_can_have_no_team_identifier(self):
        parsed = signing.parse_signing_identity(
            ".", STABLE_REPORT, STABLE_REQUIREMENT
        )
        self.assertIsNone(parsed.team_identifier)
        self.assertEqual(parsed.signature, "certificate")
        self.assertEqual(signing.stable_identity_errors([parsed], True), [])

    def test_adhoc_identity_fails_when_stable_identity_is_required(self):
        parsed = signing.parse_signing_identity(".", AD_HOC_REPORT, AD_HOC_REQUIREMENT)
        errors = signing.stable_identity_errors([parsed], True)
        self.assertTrue(any("signed ad-hoc" in error for error in errors))
        self.assertTrue(any("CDHash" in error for error in errors))

    def test_adhoc_identity_is_allowed_without_strict_check(self):
        parsed = signing.parse_signing_identity(".", AD_HOC_REPORT, AD_HOC_REQUIREMENT)
        self.assertEqual(signing.stable_identity_errors([parsed], False), [])

    def test_adhoc_identity_without_requirement_is_allowed_without_strict_check(self):
        parsed = signing.parse_signing_identity(
            ".", AD_HOC_REPORT, AD_HOC_WITHOUT_REQUIREMENT
        )
        self.assertEqual(parsed.designated_requirement, "")
        self.assertEqual(signing.stable_identity_errors([parsed], False), [])

    def test_adhoc_identity_without_requirement_fails_strict_check(self):
        parsed = signing.parse_signing_identity(
            ".", AD_HOC_REPORT, AD_HOC_WITHOUT_REQUIREMENT
        )
        errors = signing.stable_identity_errors([parsed], True)
        self.assertTrue(any("signed ad-hoc" in error for error in errors))
        self.assertTrue(any("no designated requirement" in error for error in errors))

    def test_certificate_without_requirement_fails_strict_check(self):
        parsed = signing.parse_signing_identity(
            ".", STABLE_REPORT, AD_HOC_WITHOUT_REQUIREMENT
        )
        errors = signing.stable_identity_errors([parsed], True)
        self.assertTrue(any("no designated requirement" in error for error in errors))

    def test_cdhash_requirement_fails_even_with_certificate_authority(self):
        parsed = identity(requirement='cdhash H"' + "a" * 40 + '"')
        errors = signing.stable_identity_errors([parsed], True)
        self.assertTrue(any("depends on CDHash" in error for error in errors))

    def test_cdhash_change_does_not_fail_the_identity_baseline(self):
        previous = identity(cdhash="a" * 40)
        current = identity(cdhash="b" * 40)
        self.assertEqual(signing.baseline_errors([current], [previous]), [])

    def test_designated_requirement_change_fails_the_baseline(self):
        previous = identity()
        current = identity(
            requirement='identifier "com.wyz.covio" and certificate root = H"ffffffff"'
        )
        errors = signing.baseline_errors([current], [previous])
        self.assertTrue(any("designated requirement changed" in error for error in errors))

    def test_nested_code_change_fails_the_baseline(self):
        previous = [identity()]
        current = [identity(), identity(path="MacOS/CovioHelper")]
        errors = signing.baseline_errors(current, previous)
        self.assertTrue(any("nested code appeared" in error for error in errors))

    def test_inspect_app_verifies_nested_code_with_deep_strict(self):
        results = [
            signing.CommandResult(0, "", "validated"),
            signing.CommandResult(0, STABLE_REPORT, ""),
            signing.CommandResult(0, STABLE_REQUIREMENT, ""),
            signing.CommandResult(0, HELPER_REPORT, ""),
            signing.CommandResult(0, HELPER_REQUIREMENT, ""),
        ]
        with tempfile.TemporaryDirectory() as directory:
            app = pathlib.Path(directory) / "Covio.app"
            (app / "Contents" / "MacOS").mkdir(parents=True)
            (app / "Contents" / "MacOS" / "CovioHelper").write_text(
                "helper", encoding="utf-8"
            )
            with mock.patch.object(signing, "_run_codesign", side_effect=results) as run:
                identities = signing.inspect_app(app)

        self.assertEqual([item.path for item in identities], [".", "MacOS/CovioHelper"])
        self.assertEqual(run.call_args_list[0].args[0][:4], [
            "--verify",
            "--deep",
            "--strict",
            "--verbose=2",
        ])
        self.assertIn("--deep", run.call_args_list[1].args[0])

    def test_baseline_round_trip_preserves_requirement_and_cdhash(self):
        expected = [identity(), identity(path="MacOS/CovioHelper")]
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "baseline.json"
            signing.write_baseline(path, expected)
            actual = signing.load_baseline(path)
        self.assertEqual(actual, tuple(expected))

    def test_non_object_baseline_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "baseline.json"
            path.write_text("[]", encoding="utf-8")
            with self.assertRaisesRegex(signing.SigningError, "not an object"):
                signing.load_baseline(path)


if __name__ == "__main__":
    unittest.main()
