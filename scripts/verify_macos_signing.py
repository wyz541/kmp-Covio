#!/usr/bin/env python3
"""Verify that a macOS development build keeps a TCC-stable signing identity."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Sequence


CODESIGN = "/usr/bin/codesign"
BASELINE_SCHEMA_VERSION = 1


class SigningError(RuntimeError):
    """Raised when codesign output cannot be read or verified."""


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str

    @property
    def output(self) -> str:
        return "\n".join(value for value in (self.stdout, self.stderr) if value).strip()


@dataclass(frozen=True)
class SigningIdentity:
    path: str
    identifier: str
    signature: str
    authority: str | None
    team_identifier: str | None
    cdhash: str
    designated_requirement: str


def _run_codesign(arguments: Sequence[str]) -> CommandResult:
    completed = subprocess.run(
        [CODESIGN, *arguments],
        capture_output=True,
        check=False,
        text=True,
    )
    return CommandResult(completed.returncode, completed.stdout, completed.stderr)


def _report_field(report: str, name: str) -> str | None:
    match = re.search(rf"^{re.escape(name)}=(.*)$", report, re.MULTILINE)
    return match.group(1).strip() if match else None


def nested_code_paths(report: str) -> tuple[str, ...]:
    paths = []
    for match in re.finditer(r"^Nested=(.*)$", report, re.MULTILINE):
        value = match.group(1).strip()
        if value and value not in paths:
            paths.append(value)
    return tuple(paths)


def parse_signing_identity(
    relative_path: str,
    signing_report: str,
    requirement_report: str,
) -> SigningIdentity:
    identifier = _report_field(signing_report, "Identifier")
    if not identifier:
        raise SigningError(f"{relative_path}: codesign output has no Identifier")

    authority = _report_field(signing_report, "Authority")
    team_identifier = _report_field(signing_report, "TeamIdentifier")
    if team_identifier == "not set":
        team_identifier = None

    if re.search(r"^Signature=adhoc$", signing_report, re.MULTILINE):
        signature = "adhoc"
    elif authority:
        signature = "certificate"
    else:
        signature = "unknown"

    requirement_match = re.search(
        r"^designated =>\s*(.+)$", requirement_report, re.MULTILINE
    )
    if requirement_match is None:
        suffix = " (ad-hoc signature)" if signature == "adhoc" else ""
        raise SigningError(
            f"{relative_path}: codesign output has no designated requirement{suffix}"
        )
    requirement = requirement_match.group(1).strip()
    if not requirement:
        raise SigningError(
            f"{relative_path}: codesign output has an empty designated requirement"
        )

    cdhash = _report_field(signing_report, "CDHash") or ""
    return SigningIdentity(
        path=relative_path,
        identifier=identifier,
        signature=signature,
        authority=authority,
        team_identifier=team_identifier,
        cdhash=cdhash,
        designated_requirement=requirement,
    )


def _inspect_code(
    path: Path,
    relative_path: str,
    *,
    deep: bool = False,
) -> tuple[SigningIdentity, str]:
    report_args = ["-dvvv"]
    if deep:
        report_args.append("--deep")
    report_args.append(str(path))
    signing_report = _run_codesign(report_args)
    if signing_report.returncode != 0:
        raise SigningError(
            f"{relative_path}: codesign could not read the signature\n"
            f"{signing_report.output}"
        )

    requirement_report = _run_codesign(["-d", "-r-", str(path)])
    if requirement_report.returncode != 0:
        raise SigningError(
            f"{relative_path}: codesign could not read the designated requirement\n"
            f"{requirement_report.output}"
        )

    identity = parse_signing_identity(
        relative_path,
        signing_report.output,
        requirement_report.output,
    )
    return identity, signing_report.output


def inspect_app(app: Path) -> tuple[SigningIdentity, ...]:
    if not app.is_dir():
        raise SigningError(f"app bundle does not exist: {app}")

    verification = _run_codesign(
        ["--verify", "--deep", "--strict", "--verbose=2", str(app)]
    )
    if verification.returncode != 0:
        raise SigningError(
            "nested code signature verification failed\n" f"{verification.output}"
        )

    app_identity, app_report = _inspect_code(app, ".", deep=True)
    identities = [app_identity]
    for relative_path in nested_code_paths(app_report):
        nested_path = app / "Contents" / relative_path
        if not nested_path.exists():
            raise SigningError(
                f"{relative_path}: nested code listed by codesign does not exist"
            )
        identity, _ = _inspect_code(nested_path, relative_path)
        identities.append(identity)
    return tuple(identities)


def stable_identity_errors(
    identities: Sequence[SigningIdentity],
    require_stable: bool,
) -> list[str]:
    if not require_stable:
        return []

    errors: list[str] = []
    for identity in identities:
        name = "app" if identity.path == "." else identity.path
        if identity.signature == "adhoc":
            errors.append(f"{name} is signed ad-hoc")
        elif identity.signature != "certificate":
            errors.append(f"{name} has no readable signing certificate")
        elif not identity.authority:
            errors.append(f"{name} has no signing Authority")

        if "cdhash" in identity.designated_requirement.lower():
            errors.append(
                f"{name} designated requirement depends on CDHash instead of a certificate"
            )
    return errors


def baseline_errors(
    identities: Sequence[SigningIdentity],
    baseline: Sequence[SigningIdentity],
) -> list[str]:
    current_by_path = {identity.path: identity for identity in identities}
    baseline_by_path = {identity.path: identity for identity in baseline}
    errors: list[str] = []

    removed = sorted(baseline_by_path.keys() - current_by_path.keys())
    added = sorted(current_by_path.keys() - baseline_by_path.keys())
    for path in removed:
        errors.append(f"{path}: nested code disappeared since the baseline")
    for path in added:
        errors.append(f"{path}: nested code appeared since the baseline")

    for path in sorted(current_by_path.keys() & baseline_by_path.keys()):
        current = current_by_path[path]
        previous = baseline_by_path[path]
        name = "app" if path == "." else path
        if current.identifier != previous.identifier:
            errors.append(
                f"{name} Identifier changed: {previous.identifier!r} -> "
                f"{current.identifier!r}"
            )
        if current.designated_requirement != previous.designated_requirement:
            errors.append(
                f"{name} designated requirement changed: "
                f"{previous.designated_requirement!r} -> "
                f"{current.designated_requirement!r}"
            )
    return errors


def load_baseline(path: Path) -> tuple[SigningIdentity, ...]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SigningError(f"cannot read signing baseline {path}: {error}") from error

    if not isinstance(payload, dict):
        raise SigningError(f"signing baseline is not an object: {path}")
    if payload.get("schemaVersion") != BASELINE_SCHEMA_VERSION:
        raise SigningError(f"unsupported signing baseline schema: {path}")
    code = payload.get("code")
    if not isinstance(code, list) or not code:
        raise SigningError(f"signing baseline has no code identities: {path}")

    identities: list[SigningIdentity] = []
    for value in code:
        if not isinstance(value, dict):
            raise SigningError(f"signing baseline contains a non-object entry: {path}")
        try:
            identities.append(SigningIdentity(**value))
        except TypeError as error:
            raise SigningError(f"signing baseline entry is invalid: {error}") from error
    return tuple(identities)


def write_baseline(
    path: Path,
    identities: Sequence[SigningIdentity],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schemaVersion": BASELINE_SCHEMA_VERSION,
        "code": [asdict(identity) for identity in identities],
    }
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _print_identity(identity: SigningIdentity) -> None:
    name = "app" if identity.path == "." else identity.path
    team = identity.team_identifier or "not set (allowed for self-signed)"
    print(f"{name}: Identifier={identity.identifier}")
    print(f"{name}: Signature={identity.signature}")
    print(f"{name}: Authority={identity.authority or '<missing>'}")
    print(f"{name}: TeamIdentifier={team}")
    print(f"{name}: CDHash={identity.cdhash or '<missing>'}")
    print(f"{name}: designated => {identity.designated_requirement}")


def _print_hints(errors: Sequence[str]) -> None:
    joined = "\n".join(errors).lower()
    if "ad-hoc" in joined or "no readable signing certificate" in joined:
        print(
            "hint: run bash scripts/setup-local-signing.sh, then rebuild.",
            file=sys.stderr,
        )
        print(
            "hint: certificate setup is documented in "
            "docs/adr/adr-0005-local-code-signing.md.",
            file=sys.stderr,
        )
    if "cdhash" in joined:
        print(
            "hint: sign with the fixed Covio Dev certificate instead of ad-hoc.",
            file=sys.stderr,
        )
    if "changed" in joined or "baseline" in joined:
        print(
            "hint: delete the build baseline only when a certificate or "
            "Bundle ID change is intentional.",
            file=sys.stderr,
        )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Verify a TCC-stable macOS development signing identity."
    )
    parser.add_argument("app", type=Path, help="Path to the Covio.app bundle.")
    parser.add_argument(
        "--require-stable",
        action="store_true",
        help="Reject ad-hoc and CDHash-based designated requirements.",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        help="Compare against this baseline. Create it on the first successful run.",
    )
    args = parser.parse_args(argv)

    require_stable = args.require_stable or args.baseline is not None
    try:
        identities = inspect_app(args.app)
        errors = stable_identity_errors(identities, require_stable)
        if args.baseline is not None and args.baseline.exists():
            errors.extend(baseline_errors(identities, load_baseline(args.baseline)))
    except SigningError as error:
        print(f"error: {error}", file=sys.stderr)
        _print_hints([str(error)])
        return 1

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        _print_hints(errors)
        for identity in identities:
            _print_identity(identity)
        return 1

    if args.baseline is not None:
        write_baseline(args.baseline, identities)

    for identity in identities:
        _print_identity(identity)
    if require_stable:
        print("Signing identity is stable for TCC.")
    else:
        print(
            "Ad-hoc or unpinned signing is allowed, but TCC may ask again "
            "after a rebuild."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
