# Covio 工作约定

本文件是 agent 的强制契约。Codex 直接读本文件。Claude Code 通过 `CLAUDE.md` 导入。

## 1. 项目基线

Covio 是 macOS 菜单栏应用。界面是 SwiftUI 宿主，放在 `macosApp/`。
共享领域逻辑是 KMP 模块，放在 `kmpDomain/`。
构建系统是 Amper 0.12.1，不是 Gradle。
改完跑 `bash scripts/test-all.sh`。改了 UI 的还要在真机验收，并按 `docs/process/workflow.md` 的「Visual verification」补截图。截图缺失时，不得关闭 issue。
主干是 `main`。

## 2. 流程

```text
想法 → 调研报告 → 决策 → Issue → 交付
                                └─ 大功能：父 issue 加子 issue
                                └─ 小功能：直接做
```

1. 调研报告放 `docs/research/<主题>/`。格式见 `docs/research/AUTHORING.md`。
2. 决策放 `docs/adr/adr-NNNN-<slug>.md`。模板见 `docs/adr/adr-template.md`。
3. Issue 建在 GitHub 上。仓库里不放 issue 定义文件，不设本地编号。

## 3. 大功能与小功能

大功能建一个父 issue，拆成子 issue，用 GitHub 原生 sub-issue 关联。
进度由 GitHub 自动汇总。不要另外维护进度表。
小功能建一个 issue，直接做。

一个子 issue 的粒度是一个会话能做完，对应一条分支和一个 PR。

## 4. 工作流

流程定义在 `docs/process/workflow.md`。本文件管执行。每次会话按下面的规则做。

1. 开场先归位。判断本次任务在 S1 到 S7 中的哪一步，按该步的条目与完成标准推进。
2. 想法不确定做法时走 S1 与 S2。提交人写问题、受影响的人和一个场景，不写解法。
3. 做法有未知项时开 Research issue。一个 spike 只回答一个问题。时间盒不超 3 个工作日。
4. 调研结论写在 issue 正文，不写评论。正文含结论、依据和后续动作。结论未写回正文前不关 issue。
5. 长期决策进 S4。写新 ADR 走 PR，合并前 Status 改成 `accepted`。
6. 大功能走 S5 建 Feature。每个 sub-issue 写一行验收标准，工期 1 到 3 天。
7. 涉及 UI 变化时先出 web 预览。预览通过评审再动工。见 `docs/process/workflow.md` 的设计闸门。
   UI issue 的正文必须使用 `Visual verification`。亮色和深色各放一组 `Before`/`After` 表。
8. 引用另一个对象时走 S6。值未定时写 `pending`，5 个工作日内回填。
9. 对象用标签区分。建 issue 时带对应的标签：调研 `research`，大功能 `feature`，小功能与 sub-issue `task`。
10. 个人账号没有 issue types 与 issue fields。不要用 `--type`，也不要找 issue fields。
   字段用 Project 8 的字段，名字见 `docs/process/project-fields.md`。
   Start date 与 Target date 只在 Project 里维护，不写进 issue 正文。
11. 需要你在 Web 界面操作的步骤，写明操作位置，不要跳过。

## 5. 文档

改动涉及行为时，同步改文档。

| 知识 | 位置 |
| --- | --- |
| 设计合同 | `docs/covio-design-contract.json` |
| 架构决策 | `docs/adr/` |
| 目标架构 | `docs/design/` |
| 界面打样 | `designPreview/`，读法见 `docs/design/design-preview.md` |
| UI 截图 | `docs/design/previews/` |
| 研究结论 | `docs/research/` |
| 工作流规则 | `docs/process/workflow.md` |
| Project 字段 | `docs/process/project-fields.md` |
| 进度 | [Project 8](https://github.com/users/wyz541/projects/8) |

文档用中文。命令、路径、API 名称和版本号保留原文。不写本机绝对路径。

## 6. commit

```text
Add the workbench store

Refs #27
Co-Authored-By: Claude Code <noreply@anthropic.com>
```

1. 标题行用英文祈使句，首字母大写，不超过 72 字符，不加句号，不加 `feat:` 这类前缀。
2. 有对应 issue 时在正文写 `Refs #N`。没有就不写。
3. agent 创建的提交加 `Co-Authored-By: Claude Code <noreply@anthropic.com>`。

不要用 `git commit` 不带 `-m`。

## 7. 禁止

1. 禁止直接向 `main` 推送。改 `main` 走 PR。
2. 禁止 `git add -A` 或 `git add .`。多个会话共用一个工作目录，会扫进别人的文件。
3. 禁止把本机绝对路径写进仓库文件。
4. 改设计合同后要重跑 `scripts/generate-contract-constants.py`。
