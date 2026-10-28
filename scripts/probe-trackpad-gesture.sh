#!/bin/bash
# 触控板多指手势探针。用于 `docs/research/trackpad-gesture-entry/` 的验证案例。
#
# 用法：
#   bash scripts/probe-trackpad-gesture.sh symbols           # 列出私有框架的符号
#   bash scripts/probe-trackpad-gesture.sh devices           # 枚举多触点设备
#   bash scripts/probe-trackpad-gesture.sh listen [秒数] [手指数] # 采集接触帧，默认 20 秒、4 指
#   bash scripts/probe-trackpad-gesture.sh accessors         # 逐个调用 MTDeviceGet* 访问器
#
# 警告：`listen` 会调用 `MTDeviceStart` 启动内建触控板。
# 脚本在退出前调用 `MTDeviceStop` 并注销回调。
# 不要在正在使用触控板时运行。
#
# 本脚本只读。它不写系统设置，不改应用配置。
#
# 本脚本兼容 macOS 自带的 bash 3.2。不要引入关联数组（declare -A）和 mapfile。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MODE="${1:-}"
DURATION="${2:-20}"
FINGERS="${3:-4}"

if ! [[ "$FINGERS" =~ ^[1-9]$|^10$ ]]; then
  echo "手指数必须是 1 到 10。" >&2
  exit 2
fi

if [ -z "$MODE" ]; then
  sed -n '2,17p' "$0"
  exit 2
fi

# 私有框架不在磁盘上留二进制，dyld 从共享缓存解析。所以只能用 dlopen，
# 不能用 ls 或 nm 判断可用性。
write_common() {
  cat > "$WORK/common.h" <<'EOF'
#ifndef COVIO_PROBE_COMMON_H
#define COVIO_PROBE_COMMON_H

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>

typedef void *MTDeviceRef;

/* MTTouch 的字段顺序来自公开的逆向资料。字段名只用于阅读。 */
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint pos, vel; } MTVector;
typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerID;
    int handID;
    MTVector normalized;
    float size;
    int zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector mm;
    int zero2[2];
    float density;
} MTTouch;

static const char *MT_PATH =
    "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport";

static void *mt_open(void) {
    void *handle = dlopen(MT_PATH, RTLD_NOW);
    if (!handle) {
        fprintf(stderr, "dlopen 失败：%s\n", dlerror());
        fprintf(stderr, "本机不支持私有 MultitouchSupport.framework。\n");
    }
    return handle;
}

#endif
EOF
}

case "$MODE" in
  symbols)
    write_common
    cat > "$WORK/main.c" <<'EOF'
#include "common.h"

int main(void) {
    void *handle = mt_open();
    if (!handle) return 1;

    const char *names[] = {
        "MTDeviceCreateList", "MTDeviceCreateDefault", "MTDeviceCreateFromDeviceID",
        "MTDeviceStart", "MTDeviceStop", "MTDeviceIsRunning", "MTDeviceIsBuiltIn",
        "MTDeviceIsAlive", "MTDeviceIsAvailable", "MTDeviceGetFamilyID",
        "MTDeviceGetDeviceID", "MTDeviceGetTransportMethod", "MTDeviceGetVersion",
        "MTRegisterContactFrameCallback", "MTRegisterContactFrameCallbackWithRefcon",
        "MTUnregisterContactFrameCallback", "MTDeviceCreateMultitouchRunLoopSource",
        NULL
    };

    printf("%-46s %s\n", "符号", "状态");
    for (int i = 0; names[i]; i++) {
        printf("%-46s %s\n", names[i], dlsym(handle, names[i]) ? "存在" : "缺失");
    }
    return 0;
}
EOF
    clang -o "$WORK/probe" "$WORK/main.c" -framework CoreFoundation
    "$WORK/probe"
    ;;

  devices)
    write_common
    cat > "$WORK/main.c" <<'EOF'
#include "common.h"

int main(void) {
    void *handle = mt_open();
    if (!handle) return 1;

    CFArrayRef (*list_fn)(void) = (CFArrayRef (*)(void))dlsym(handle, "MTDeviceCreateList");
    int (*is_builtin)(MTDeviceRef) = (int (*)(MTDeviceRef))dlsym(handle, "MTDeviceIsBuiltIn");
    int (*is_running)(MTDeviceRef) = (int (*)(MTDeviceRef))dlsym(handle, "MTDeviceIsRunning");
    int (*is_available)(MTDeviceRef) = (int (*)(MTDeviceRef))dlsym(handle, "MTDeviceIsAvailable");

    if (!list_fn) { fprintf(stderr, "缺少 MTDeviceCreateList。\n"); return 1; }

    CFArrayRef list = list_fn();
    if (!list) { fprintf(stderr, "MTDeviceCreateList 返回 NULL。\n"); return 1; }

    CFIndex count = CFArrayGetCount(list);
    printf("设备数：%ld\n", (long)count);
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(list, i);
        printf("  [%ld] 内建=%d 运行中=%d 可用=%d\n", (long)i,
               is_builtin ? is_builtin(device) : -1,
               is_running ? is_running(device) : -1,
               is_available ? is_available(device) : -1);
    }

    /* MTDeviceGetFamilyID / MTDeviceGetDeviceID 在 macOS 27.0.1 上会崩溃。
       这里故意不调用。用 `accessors` 模式单独验证。 */
    printf("注意：本模式不调用 MTDeviceGet* 访问器。用 accessors 模式单独验证。\n");
    return 0;
}
EOF
    clang -o "$WORK/probe" "$WORK/main.c" -framework CoreFoundation
    "$WORK/probe"
    ;;

  accessors)
    write_common
    cat > "$WORK/main.c" <<'EOF'
#include "common.h"
#include <string.h>

/* 每个访问器在独立子进程里调用。子进程崩溃不影响父进程，
   所以可以一次跑完所有访问器并拿到每个的退出码。 */
int main(void) {
    void *handle = mt_open();
    if (!handle) return 1;

    const char *names[] = {
        "MTDeviceIsBuiltIn", "MTDeviceIsRunning", "MTDeviceIsAlive", "MTDeviceIsAvailable",
        "MTDeviceGetFamilyID", "MTDeviceGetDeviceID", "MTDeviceGetTransportMethod",
        "MTDeviceGetVersion", NULL
    };

    printf("%-30s %-8s %s\n", "符号", "退出码", "结果");
    for (int i = 0; names[i]; i++) {
        fflush(stdout);
        pid_t pid = fork();
        if (pid == 0) {
            /* 子进程：安静地调用一个访问器。 */
            CFArrayRef (*list_fn)(void) = (CFArrayRef (*)(void))dlsym(handle, "MTDeviceCreateList");
            CFArrayRef list = list_fn();
            MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(list, 0);
            void *symbol = dlsym(handle, names[i]);
            if (!symbol) _exit(3);
            int (*fn)(MTDeviceRef) = (int (*)(MTDeviceRef))symbol;
            int result = fn(device);
            _exit(result == 0 ? 0 : 1);
        }
        int status = 0;
        waitpid(pid, &status, 0);
        if (WIFSIGNALED(status)) {
            printf("%-30s %-8d 崩溃（信号 %d）\n", names[i], 128 + WTERMSIG(status), WTERMSIG(status));
        } else {
            printf("%-30s %-8d 正常\n", names[i], WEXITSTATUS(status));
        }
    }
    return 0;
}
EOF
    # waitpid 需要 sys/wait.h 和 unistd.h。
    sed -i '' 's|#include <string.h>|#include <string.h>\n#include <sys/wait.h>\n#include <unistd.h>|' "$WORK/main.c"
    clang -o "$WORK/probe" "$WORK/main.c" -framework CoreFoundation
    "$WORK/probe"
    ;;

  listen)
    write_common
    cat > "$WORK/main.c" <<'EOF'
#include "common.h"
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

static MTDeviceRef g_device = NULL;
static void (*g_stop)(MTDeviceRef, int) = NULL;
static void (*g_unregister)(MTDeviceRef, void *) = NULL;
static void *g_callback = NULL;

static int g_frames = 0;
static int g_max_fingers = 0;
static int g_counts[16];
static int g_target_fingers = 4;
static double g_target_x_first = 0.0;
static double g_target_x_last = 0.0;
static double g_target_y_first = 0.0;
static double g_target_y_last = 0.0;
static int g_target_frames = 0;
static double g_target_t0 = 0.0;

static void cleanup(void) {
    if (g_device && g_stop) g_stop(g_device, 0);
    if (g_device && g_unregister && g_callback) g_unregister(g_device, g_callback);
}

static void on_signal(int sig) {
    (void)sig;
    cleanup();
    _exit(0);
}

static int on_frame(MTDeviceRef device, MTTouch *touches, int count, double timestamp, int frame) {
    (void)device; (void)frame;
    g_frames++;
    if (count > 0 && count < 16) g_counts[count]++;
    if (count > g_max_fingers) g_max_fingers = count;

    if (count == g_target_fingers) {
        double sum_x = 0.0;
        double sum_y = 0.0;
        for (int i = 0; i < count; i++) {
            sum_x += touches[i].normalized.pos.x;
            sum_y += touches[i].normalized.pos.y;
        }
        double mean_x = sum_x / count;
        double mean_y = sum_y / count;
        if (g_target_frames == 0) {
            g_target_x_first = mean_x;
            g_target_y_first = mean_y;
            g_target_t0 = timestamp;
        }
        g_target_x_last = mean_x;
        g_target_y_last = mean_y;
        g_target_frames++;
    } else if (g_target_frames > 0) {
        /* 一次目标手指数接触结束，报告这一段的位移。 */
        fprintf(stdout, "%d 指段：%d 帧，x %.4f -> %.4f，y %.4f -> %.4f，位移 %.4f，时长 %.3f 秒\n",
                g_target_fingers, g_target_frames,
                g_target_x_first, g_target_x_last,
                g_target_y_first, g_target_y_last,
                g_target_y_last - g_target_y_first, timestamp - g_target_t0);
        fflush(stdout);
        g_target_frames = 0;
    }
    return 0;
}

int main(int argc, char **argv) {
    int seconds = argc > 1 ? atoi(argv[1]) : 20;
    if (seconds <= 0) seconds = 20;
    const char *fingers_text = getenv("COVIO_PROBE_FINGERS");
    if (fingers_text) {
        g_target_fingers = atoi(fingers_text);
        if (g_target_fingers < 1 || g_target_fingers > 10) g_target_fingers = 4;
    }

    void *handle = mt_open();
    if (!handle) return 1;

    CFArrayRef (*list_fn)(void) = (CFArrayRef (*)(void))dlsym(handle, "MTDeviceCreateList");
    void (*reg)(MTDeviceRef, void *) = (void (*)(MTDeviceRef, void *))dlsym(handle, "MTRegisterContactFrameCallback");
    g_unregister = (void (*)(MTDeviceRef, void *))dlsym(handle, "MTUnregisterContactFrameCallback");
    void (*start)(MTDeviceRef, int) = (void (*)(MTDeviceRef, int))dlsym(handle, "MTDeviceStart");
    g_stop = (void (*)(MTDeviceRef, int))dlsym(handle, "MTDeviceStop");
    int (*running)(MTDeviceRef) = (int (*)(MTDeviceRef))dlsym(handle, "MTDeviceIsRunning");

    if (!list_fn || !reg || !start || !g_stop) {
        fprintf(stderr, "缺少必需符号。私有路径不可用。\n");
        return 1;
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGALRM, on_signal);

    CFArrayRef list = list_fn();
    g_device = (MTDeviceRef)CFArrayGetValueAtIndex(list, 0);

    reg(g_device, (void *)on_frame);
    g_callback = (void *)on_frame;
    start(g_device, 0);

    fprintf(stdout, "已启动。运行中=%d。\n", running ? running(g_device) : -1);
    fprintf(stdout, "请在 %d 秒内做手势。记录 %d 指接触段；同时做其他手指数动作用于对照。\n", seconds, g_target_fingers);
    fflush(stdout);

    alarm(seconds + 5);
    sleep(seconds);

    cleanup();
    fprintf(stdout, "\n汇总\n");
    fprintf(stdout, "  总帧数：%d\n", g_frames);
    fprintf(stdout, "  最大手指数：%d\n", g_max_fingers);
    for (int i = 1; i < 16; i++) {
        if (g_counts[i] > 0) fprintf(stdout, "  %d 指：%d 帧\n", i, g_counts[i]);
    }
    if (g_frames == 0) {
        fprintf(stdout, "  没有收到任何帧。确认在采集期间触摸了触控板。\n");
    }
    return 0;
}
EOF
    clang -o "$WORK/probe" "$WORK/main.c" -framework CoreFoundation
    echo "编译完成：$WORK/probe"
    echo "启动内建触控板采集。按 Control+C 可以提前结束。"
    echo
    COVIO_PROBE_FINGERS="$FINGERS" "$WORK/probe" "$DURATION"
    ;;

  *)
    echo "未知模式：$MODE" >&2
    sed -n '2,17p' "$0" >&2
    exit 2
    ;;
esac
