#!/usr/bin/env python3
"""Fetch, validate, and verify the fixed local file-naming model."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFESTS = {
    "2b": ROOT / "macosApp/src/AutoNaming/FileNamingModelManifest.json",
    "4b": ROOT / "macosApp/src/AutoNaming/FileNamingModelManifest-balanced4B.json",
    "8b": ROOT / "macosApp/src/AutoNaming/FileNamingModelManifest-highQuality8B.json",
    "30b-a3b": ROOT / "macosApp/src/AutoNaming/FileNamingModelManifest-heavy30BA3B.json",
}
DEFAULT_MANIFEST = MANIFESTS["2b"]
EXPECTED_MODELS = {
    "2b": (
        "mlx-community/Qwen3-VL-2B-Instruct-4bit",
        "9c4f5209e57b31f4b9dfba735de3fb983739c9cc",
    ),
    "4b": (
        "mlx-community/Qwen3-VL-4B-Instruct-4bit",
        "2fd8dacbdb8f1e54b8c005f081ec5bf79c56376b",
    ),
    "8b": (
        "mlx-community/Qwen3-VL-8B-Instruct-4bit",
        "defcdea7cc7a4b0858fea563cbbce171d328e457",
    ),
    "30b-a3b": (
        "lmstudio-community/Qwen3-VL-30B-A3B-Instruct-MLX-4bit",
        "61c11f42d7bc01e00f5ea7f2e667c0a216f48397",
    ),
}
ATTRIBUTION = {
    "2b": ROOT / "third_party/models/Qwen3-VL-2B-Instruct",
    "4b": ROOT / "third_party/models/Qwen3-VL-4B-Instruct",
    "8b": ROOT / "third_party/models/Qwen3-VL-8B-Instruct",
    "30b-a3b": ROOT / "third_party/models/Qwen3-VL-30B-A3B-Instruct",
}
HF_BASE = "https://huggingface.co"


class ModelError(RuntimeError):
    pass


def load_manifest(path: Path) -> dict:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ModelError(f"cannot read manifest: {error}") from error
    validate_manifest(manifest)
    return manifest


def validate_manifest(manifest: dict) -> None:
    required = {
        "schemaVersion",
        "tier",
        "modelID",
        "revision",
        "displayName",
        "runtimeDirectory",
        "license",
        "licenseFile",
        "noticeFile",
        "totalBytes",
        "files",
    }
    if set(manifest) != required:
        raise ModelError("manifest keys do not match schema")
    if manifest["schemaVersion"] != 1:
        raise ModelError("unsupported manifest schema")
    tier = manifest["tier"]
    if tier not in EXPECTED_MODELS:
        raise ModelError(f"unknown model tier: {tier!r}")
    expected_model, expected_revision = EXPECTED_MODELS[tier]
    if manifest["modelID"] != expected_model:
        raise ModelError("modelID does not match the tier allowlist")
    if manifest["revision"] != expected_revision:
        raise ModelError("revision does not match the pinned model revision")
    if manifest["license"] != "Apache-2.0":
        raise ModelError("unexpected model license")
    for key in ("licenseFile", "noticeFile"):
        name = manifest[key]
        if not isinstance(name, str) or not name or "/" in name or name in {".", ".."}:
            raise ModelError(f"invalid {key}: {name!r}")
    if not str(manifest["runtimeDirectory"]).startswith("Models/"):
        raise ModelError("runtimeDirectory must start with Models/")

    names: set[str] = set()
    total = 0
    for item in manifest["files"]:
        if set(item) != {"path", "size", "sha256"}:
            raise ModelError("file entry keys do not match schema")
        name = item["path"]
        if not isinstance(name, str) or not name or "/" in name or name in {".", ".."}:
            raise ModelError(f"invalid model file path: {name!r}")
        if name in names:
            raise ModelError(f"duplicate model file: {name}")
        names.add(name)
        size = item["size"]
        if not isinstance(size, int) or size <= 0:
            raise ModelError(f"invalid size for {name}")
        digest = item["sha256"]
        if not isinstance(digest, str) or len(digest) != 64:
            raise ModelError(f"invalid SHA-256 for {name}")
        try:
            int(digest, 16)
        except ValueError as error:
            raise ModelError(f"invalid SHA-256 for {name}") from error
        total += size

    if total != manifest["totalBytes"]:
        raise ModelError("manifest totalBytes does not match file sizes")
    attribution = ATTRIBUTION[tier]
    for name in ("LICENSE", "NOTICE"):
        path = attribution / name
        if not path.is_file():
            raise ModelError(f"missing model attribution file: {path.relative_to(ROOT)}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def verify_directory(directory: Path, manifest_path: Path) -> None:
    manifest = load_manifest(manifest_path)
    if not directory.is_dir():
        raise ModelError(f"model directory does not exist: {directory}")
    copied_manifest = directory / "FileNamingModelManifest.json"
    if not copied_manifest.is_file():
        raise ModelError("model directory has no manifest")
    if copied_manifest.read_bytes() != manifest_path.read_bytes():
        raise ModelError("model directory manifest differs from the source manifest")

    for item in manifest["files"]:
        path = directory / item["path"]
        if path.is_symlink() or not path.is_file():
            raise ModelError(f"missing regular model file: {item['path']}")
        size = path.stat().st_size
        if size != item["size"]:
            raise ModelError(f"size mismatch for {item['path']}: {size} != {item['size']}")
        digest = sha256_file(path)
        if digest != item["sha256"]:
            raise ModelError(f"SHA-256 mismatch for {item['path']}")

    for name in (manifest["licenseFile"], manifest["noticeFile"]):
        if not (directory / name).is_file():
            raise ModelError(f"model directory is missing {name}")

    print(
        f"Model verified: {manifest['displayName']} @ {manifest['revision']}, "
        f"{len(manifest['files'])} files, {manifest['totalBytes']} bytes"
    )


def download(directory: Path, manifest_path: Path) -> None:
    manifest = load_manifest(manifest_path)
    if shutil.which("curl") is None:
        raise ModelError("curl is required")
    directory.mkdir(parents=True, exist_ok=True)
    base = (
        f"{HF_BASE}/{manifest['modelID']}/resolve/{manifest['revision']}"
    )
    for item in manifest["files"]:
        target = directory / item["path"]
        if (
            target.is_file()
            and not target.is_symlink()
            and target.stat().st_size == item["size"]
            and sha256_file(target) == item["sha256"]
        ):
            print(f"verified {item['path']}", flush=True)
            continue
        print(f"fetch {item['path']}", flush=True)
        subprocess.run(
            [
                "curl",
                "-fL",
                "--retry",
                "5",
                "--retry-all-errors",
                "--continue-at",
                "-",
                "-o",
                str(target),
                f"{base}/{item['path']}",
            ],
            check=True,
        )
    shutil.copy2(manifest_path, directory / "FileNamingModelManifest.json")
    attribution = ATTRIBUTION[manifest["tier"]]
    shutil.copy2(attribution / "LICENSE", directory / manifest["licenseFile"])
    shutil.copy2(attribution / "NOTICE", directory / manifest["noticeFile"])
    verify_directory(directory, manifest_path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("verify-manifest")
    subparsers.add_parser("verify-all")
    verify_parser = subparsers.add_parser("verify-directory")
    verify_parser.add_argument("directory", type=Path)
    fetch_parser = subparsers.add_parser("download")
    fetch_parser.add_argument("directory", type=Path)
    args = parser.parse_args()

    try:
        if args.command == "verify-manifest":
            manifest = load_manifest(args.manifest)
            print(
                f"Manifest valid: {len(manifest['files'])} files, "
                f"{manifest['totalBytes']} bytes"
            )
        elif args.command == "verify-all":
            for tier, path in MANIFESTS.items():
                manifest = load_manifest(path)
                print(
                    f"{tier}: {len(manifest['files'])} files, "
                    f"{manifest['totalBytes']} bytes"
                )
        elif args.command == "verify-directory":
            verify_directory(args.directory, args.manifest)
        else:
            download(args.directory, args.manifest)
    except (ModelError, OSError, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
