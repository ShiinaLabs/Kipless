# Kipless 自动化测试计划

Kipless 的测试体系分为三个层级：

```text
Fast CI
    ↓
Local Integration Tests
    ↓
Release Preflight
```

## 目标与边界

- GitHub Actions 只运行便宜、快速、确定性的测试。
- 真实 macOS Power Management 集成测试只在开发者自己的 Mac 上运行。
- 不等待真实睡眠、息屏、15/30/60/120 分钟 Session 或 24 小时稳定性。
- 不依赖人工点击 UI 判断核心逻辑。
- 不增加第三方运行时依赖或长期 CI 成本。
- `KiplessPowerTestHelper` 是独立测试 executable，永远不进入发布包。
- Launch at Login 的 approval UI、DMG 安装、notarization、Gatekeeper 与真实睡眠不是普通 CI 的测试项。
- `Closed Lid` 的 root helper/XPC 测试不在 Fast CI 中执行。

## Layer 1：Fast CI

触发：`push` 到 `main`、`pull_request`。

运行位置：GitHub-hosted `macos-latest`。

CI 执行：

```bash
xcodebuild test \
  -project Kipless.xcodeproj \
  -scheme Kipless \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project Kipless.xcodeproj \
  -scheme Kipless \
  -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

CI 覆盖 `WakeSessionManager`、`WakeSession`、`WakeDuration`、`WakeMode`、倒计时与设置文案。时间测试通过注入时钟完成，不使用真实等待。

CI 另外构建 `KiplessSleepHelper` target，并运行 `bash -n scripts/*.sh`；这两项只验证构建图和脚本语法，不执行真实 `pmset -a disablesleep`。

## Layer 2：Local Integration Tests

入口：

```bash
./scripts/test-integration.sh
```

集成测试使用真实 `IOPMAssertion`，通过 `pmset -g assertions` 检查创建、类型、释放和异常退出清理。所有脚本都使用 `trap cleanup EXIT`，结束时必须不存在以下 reason：

```text
Kipless is keeping your Mac awake.
```

### Power helper

构建目标：`KiplessPowerTestHelper`。

命令：

```bash
KiplessPowerTestHelper system
KiplessPowerTestHelper display
KiplessPowerTestHelper hold-system
KiplessPowerTestHelper hold-display
KiplessPowerTestHelper replace-system-display
KiplessPowerTestHelper replace-display-system
```

其中 `system` / `display` 创建对应 assertion 并短暂持有后释放；`hold-*` 持续持有直到进程结束；`replace-*` 先释放第一种 assertion，再创建第二种并持续持有。

### 必须验证的真实行为

1. System 模式创建并释放 `PreventUserIdleSystemSleep`。
2. Display 模式创建并释放 `PreventUserIdleDisplaySleep`。
3. 重复 release 不崩溃、不产生残留。
4. System → Display 与 Display → System 替换时，任何时刻最多存在一个 Kipless assertion。
5. `kill -9` 终止 `hold-system` / `hold-display` 后，macOS 在短时间内自动清理 assertion。

### Closed Lid helper 集成测试

`KiplessTests/LidAwakeIntegrationTests.swift` 通过真实的
`PrivilegedHelperClient` 和嵌入式 `KiplessSleepHelper` 验证 `SleepDisabled` 的
读取、baseline ownership、重复 acquire/release，以及 XPC connection
invalidation 后的恢复。正式的 Closed Lid mode 还会先持有
`PreventUserIdleSystemSleep` assertion，随后才创建这个 lease；任一阶段失败
都必须回滚。

这些测试默认跳过，因为它们会临时修改本机电源策略。明确确认要在当前 Mac
上执行时运行：

```bash
KIPLESS_RUN_LID_AWAKE_INTEGRATION=1 ./scripts/test-integration.sh
```

脚本未设置该变量时会明确跳过 closed-lid helper 测试，不会调用
`pmset -a disablesleep`。

## Layer 3：Release Preflight

入口：

```bash
./scripts/preflight.sh
```

执行顺序：

```text
Unit Tests
Release Build
System Assertion
Display Assertion
Assertion Replacement
Process Cleanup
App Smoke Test
Bundle Metadata
Code Signature
Final Leak Check
```

Preflight 失败立即退出 1。App smoke test 必须确认：

- Release `Kipless.app` 可以启动并保持运行。
- 进程不是立即 crash。
- 默认状态没有 Kipless assertion。
- `CFBundleIdentifier` 为 `com.kaoru.kipless`。
- `LSUIElement` 为 true。
- `LSMinimumSystemVersion` 为 14 或更高。
- `codesign --verify --deep --strict` 通过。
- 终止应用后进程退出且没有 assertion 残留。

本机普通 Preflight 允许 ad-hoc signature；Developer ID signing、notarization、staple 和 Gatekeeper 验证只由 Release workflow 负责。

成功输出包含：

```text
Kipless Preflight

✓ Unit tests
✓ Release build
✓ System assertion
✓ Display assertion
✓ Assertion replacement
✓ Process cleanup
✓ App smoke test
✓ Bundle metadata
✓ Code signature
✓ No leaked assertions

PASS
```

## GitHub Release

Release workflow 只在 `v*` tag 或手动输入版本时运行。两条路径都统一生成：

```text
version = 1.0.0
tag = v1.0.0
```

手动发布不能使用分支名作为最终 release tag。Release workflow 只负责 Archive、Developer ID 签名、导出、DMG、notarization、staple、验证与发布，不重新执行本地长集成测试。

## Release blockers

以下任一项失败都禁止发布：单位测试、Release build、System/Display assertion 创建、Stop/释放、替换、`kill -9` 清理、最终 leak check、App smoke、Bundle metadata、Developer ID signing、notarization 或 Gatekeeper 验证。

Closed-lid 功能额外要求：helper 可执行文件和 LaunchDaemon plist 必须进入正确的
App bundle 路径；在授权本机运行集成测试时，四个 baseline/lease/invalidation
场景必须通过，并且最终 `SleepDisabled` 必须回到测试开始时的值。

设置界面像素差异、Popover 动画、Launch at Login approval UI、菜单栏图标轻微视觉差异、合盖与低电量行为不属于自动发布阻塞项。

## 人工合盖测试

自动测试不能代替真实硬件验证。发布新版本前，在连接电源的 MacBook 上执行：

1. 记录当前 `SleepDisabled` baseline，并连接电源。
2. 启动一个持续运行的任务。
3. 选择 `Closed Lid` 并启动 Session。
4. 合盖 3–5 分钟。
5. 开盖，确认任务仍在继续。
6. 停止 Session，确认 baseline 已恢复。
7. 再次合盖，确认系统恢复正常睡眠行为。

本版本不实现电池阈值、温度保护、充电器策略、合盖检测或重启恢复。`Closed Lid`
是正式的第三种 `WakeMode`，不提供独立的 Lid Awake Toggle。
