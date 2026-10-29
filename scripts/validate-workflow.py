#!/usr/bin/env python3
"""校验 UI 证据的位置与模板结构。

规则来源：ADR-0023 与 ADR-0024。
Issue 阶段只写目标和表现预期。UI 代码变更的真机截图写入 PR。
Parent Feature 使用同级 Research、Task 与 Verify sub-issue。
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
ISSUE_TEMPLATES = tuple(sorted((ROOT / ".github" / "ISSUE_TEMPLATE").glob("*.yml")))
PR_TEMPLATE = ROOT / ".github" / "pull_request_template.md"
FEATURE_TEMPLATE = ROOT / ".github" / "ISSUE_TEMPLATE" / "feature.yml"
TASK_TEMPLATE = ROOT / ".github" / "ISSUE_TEMPLATE" / "task.yml"
VERIFY_TEMPLATE = ROOT / ".github" / "ISSUE_TEMPLATE" / "verify.yml"
WORKFLOW = ROOT / "docs" / "process" / "workflow.md"
AGENTS = ROOT / "AGENTS.md"
PREVIEW_README = ROOT / "docs" / "design" / "previews" / "README.md"
ADR = ROOT / "docs" / "adr" / "adr-0023-visual-verification-in-pull-requests.md"

errors: list[str] = []


def require_text(path: Path, fragments: tuple[str, ...]) -> None:
    text = path.read_text(encoding="utf-8")
    for fragment in fragments:
        if fragment not in text:
            errors.append(f"{path.relative_to(ROOT)} 缺少：{fragment}")


def main() -> int:
    if not ISSUE_TEMPLATES:
        errors.append("没有找到 Issue 模板")

    for path in ISSUE_TEMPLATES:
        text = path.read_text(encoding="utf-8")
        if "label: Visual verification" in text:
            errors.append(f"{path.relative_to(ROOT)} 仍在 Issue 阶段要求 Visual verification")
        if "id: ui_evidence" in text:
            errors.append(f"{path.relative_to(ROOT)} 仍包含 ui_evidence 字段")

    require_text(
        PR_TEMPLATE,
        (
            "## Visual verification",
            "**亮色**",
            "**深色**",
            "| Before | After |",
            "### Evidence details",
            "- Source:",
            "- Date:",
            "- Device:",
            "- OS:",
            "- Page:",
            "- State:",
            "- Commit:",
        ),
    )
    require_text(
        WORKFLOW,
        (
            "UI 代码变更的 `Visual verification` 只写在 PR",
            "PR 正文嵌入同一文件的固定 commit GitHub 图片地址",
            "UI 代码 PR 缺少截图或图片链接失效时，不得转入 ready 或合并",
            "Research、Task 与 Verify 都是 Parent Feature 的 sub-issue",
            "Verify 与 Task 同级",
            "Verify 不要求分支和 PR",
        ),
    )
    require_text(
        FEATURE_TEMPLATE,
        (
            "Research、Task 与 Verify 都是 Parent Feature 的 sub-issue",
            "Verify 与 Task 同级",
        ),
    )
    require_text(TASK_TEMPLATE, ("另建 Verify sub-issue",))
    require_text(
        VERIFY_TEMPLATE,
        (
            'labels: ["verify"]',
            "label: 验收场景",
            "label: 证据要求",
            "Verify 与 Task 同级",
        ),
    )
    require_text(
        AGENTS,
        (
            "PR 必须使用 `Visual verification`",
            "PR 不得转入 ready 或合并",
            "Verify 与 Task 同级",
            "Verify 的产出是验收证据",
        ),
    )
    require_text(PREVIEW_README, ("PR 的 `Visual verification`",))
    require_text(ADR, ("- Status：accepted", "## 决策", "PR 必须提供 `Visual verification`"))

    if errors:
        for error in errors:
            print(f"工作流校验失败：{error}", file=sys.stderr)
        print(f"{len(errors)} 条问题。", file=sys.stderr)
        return 1

    print("工作流校验通过：Research、Task、Verify 层级正确，PR 写 Visual verification。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
