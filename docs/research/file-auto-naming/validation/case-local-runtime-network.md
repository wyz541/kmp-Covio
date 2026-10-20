# Case 3：本地运行网络检查

| 项目 | 内容 |
| --- | --- |
| 文档状态 | 部分通过 |
| 执行时间 | 2026-10-20 |
| 环境 | macOS 27.0.1，arm64 |
| 运行器 | llama.cpp release `b11756` |

[返回验证目录](README.md)  
[证据附录](../evidence.md)  
[主题索引](../README.md)

## 验证目标

验证本地模型命令不依赖远程 AI 服务。
观察进程是否建立非 loopback 网络连接。

## 预检记录

| 项目 | 结果 |
| --- | --- |
| 模型路径 | 本地文件 |
| mmproj | 不需要 |
| `--offline` | 支持 |
| 网络工具 | `lsof` |
| 用户数据 | 未使用 |

## 测试前采集

命令使用本地 GGUF。
命令禁用网络下载。
进程在后台运行后执行连接检查。

## 执行步骤

前置条件：模型和文本提示存在。

命令模板：

```bash
llama-cli \
  -m "$MODEL_DIR/Qwen3VL-2B-Instruct-Q4_K_M.gguf" \
  -sys "Return plain text." \
  -f "$PROMPTS/offline.txt" \
  -n 512 -c 4096 -ngl 99 -st \
  --temp 0 --top-k 1 --jinja \
  --no-display-prompt --simple-io --log-disable \
  --offline &

pid=$!
sleep 1
lsof -nP -a -p "$pid" -i
wait "$pid"
```

预期结果：命令成功，且没有非 loopback 连接。

实际结果：

```text
rc=0
TCP 127.0.0.1:65009 (LISTEN)
TCP 127.0.0.1:65017->127.0.0.1:65009 (ESTABLISHED)
TCP 127.0.0.1:65009->127.0.0.1:65017 (ESTABLISHED)
```

错误码：无。

## 结果汇总

| 检查 | 状态 | 结论 |
| --- | --- | --- |
| 本地模型加载 | 通过 | 模型来自本地路径 |
| `--offline` | 通过 | 命令成功 |
| 非 loopback 连接 | 通过 | 未观察到 |
| Covio 应用内网络 | 未执行 | 尚无产品实现 |

## 清理记录

1. 模型进程已退出。
2. 没有系统网络设置变更。
3. 没有防火墙规则变更。
4. 合成提示可以删除。

## 更新规则

1. Covio 集成后重复此测试。
2. 必须记录应用 PID 和完整时间窗。
3. 必须检查模型加载、推理和退出三个阶段。
4. 任何非 loopback 连接都阻断发布。

## 关联文档

- [验证目录](README.md)
- [证据附录](../evidence.md)
- [主题索引](../README.md)
- [推荐方案](../solution.md)
