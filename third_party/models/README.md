# Optional local models

Covio does not bundle the 4B, 8B, or 30B-A3B weights.
The repository stores only the fixed manifests and attribution files.

## Packages

| Tier | Manifest | Attribution |
| --- | --- | --- |
| 2B | `macosApp/src/AutoNaming/FileNamingModelManifest.json` | `Qwen3-VL-2B-Instruct/` |
| 4B | `macosApp/src/AutoNaming/FileNamingModelManifest-balanced4B.json` | `Qwen3-VL-4B-Instruct/` |
| 8B | `macosApp/src/AutoNaming/FileNamingModelManifest-highQuality8B.json` | `Qwen3-VL-8B-Instruct/` |
| 30B-A3B | `macosApp/src/AutoNaming/FileNamingModelManifest-heavy30BA3B.json` | `Qwen3-VL-30B-A3B-Instruct/` |

Each package must contain `FileNamingModelManifest.json`, `LICENSE`, and `NOTICE`.
The app verifies the pinned revision, file sizes, and SHA-256 values before it registers a package.
