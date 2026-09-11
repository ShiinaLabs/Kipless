# Kipless v1.0 项目计划

## 1. 项目概述

Kipless 是一个原生 macOS 菜单栏工具，用于简单、明确地控制 Mac 的自动睡眠行为。

第一版目标不是做复杂的电源管理平台，而是提供一个可靠、轻量、无干扰的基础工具。

核心原则：

* 原生 macOS
* 菜单栏优先
* 操作简单
* 行为明确
* 无账户
* 无遥测
* 核心功能完全离线
* 不修改系统永久电源设置
* 不依赖 Shell 脚本或长期运行的外部进程
* 不加入与睡眠控制无关的功能
* v1 以稳定性和可预测性优先

---

# 2. 项目信息

```text
Product Name: Kipless
Repository: ShiinaLabs/Kipless
Bundle ID: com.kaoru.kipless
License: MPL-2.0
Platform: macOS
Minimum macOS: macOS 14
Language: Swift
UI Framework: SwiftUI
Architecture: arm64 + x86_64
Application Type: Menu Bar Utility
```

GitHub 仓库归属：

```text
ShiinaLabs/Kipless
```

Bundle ID 保持：

```text
com.kaoru.kipless
```

项目归属与 Bundle ID 命名体系独立处理。

---

# 3. v1.0 产品定位

一句话定位：

> Kipless is a lightweight macOS utility for controlling system and display sleep.

Kipless v1.0 只解决一个核心问题：

> 用户临时不希望 Mac 因空闲而睡眠时，可以快速、明确地控制这一行为。

不尝试替代 macOS 完整的电源管理系统。

---

# 4. v1.0 核心功能

## 4.1 Keep Mac Awake

阻止 Mac 因用户空闲而自动进入系统睡眠。

显示器仍然按照 macOS 自身设置正常关闭。

典型场景：

* 长时间下载
* 编译
* 渲染
* 文件处理
* 长时间运行脚本
* 后台任务
* 本地服务器

内部对应：

```text
PreventUserIdleSystemSleep
```

该模式不保证阻止：

* 合盖睡眠
* 用户主动 Sleep
* 低电量强制睡眠
* 系统级强制睡眠行为

---

## 4.2 Keep Mac + Display Awake

阻止显示器因用户空闲而自动关闭，同时保持 Mac 唤醒。

这是一个包含关系明确的独立运行模式，而不是与 Keep Mac Awake 并列启用的第二个开关。

由于 Display Idle Sleep 被阻止，该状态下系统也需要保持唤醒。

典型场景：

* 阅读
* 展示仪表盘
* 查看监控信息
* 长时间参考资料
* 展示内容
* 演示

内部对应：

```text
PreventUserIdleDisplaySleep
```

---

# 5. 明确不支持的行为

v1.0 不处理以下行为：

* 合盖后保持运行
* 阻止用户主动 Sleep
* 修改 `pmset`
* 修改系统永久睡眠设置
* 强行覆盖 macOS 电源策略
* Dark Wake 控制
* PreventSystemSleep 类型的高级控制
* 睡眠拦截 Hook
* 管理员权限操作

用户主动要求系统 Sleep 时，Kipless 不应该阻止。

---

# 6. Session 模型

Kipless 任何时候最多存在一个 Wake Session。

Session 数据模型：

```text
WakeSession
├── mode
├── startedAt
├── expiresAt?
└── duration
```

状态：

```text
Inactive
Active
```

Active 状态下包含：

```text
Mode:
- system
- display

Duration:
- timed
- indefinite
```

新的 Session 启动时不允许并存第二个 Session。

---

# 7. Duration

v1.0 提供固定预设：

```text
15 minutes
30 minutes
1 hour
2 hours
Indefinitely
```

v1.0 不做自定义 Duration。

以后有真实需求再增加。

---

# 8. Session 行为

启动 Session：

```text
Select Mode
↓
Select Duration
↓
Start
↓
Create Power Assertion
↓
Active
```

停止 Session：

```text
Stop
↓
Release Assertion
↓
Inactive
```

定时 Session：

```text
Start
↓
记录绝对 expiresAt
↓
持续根据当前时间计算剩余时间
↓
expiresAt 到达
↓
Release Assertion
↓
Inactive
```

不能仅依赖递减 Timer 保存时间。

必须使用真实截止时间：

```text
expiresAt
```

避免：

* App 卡顿导致时间漂移
* Mac 唤醒后计时错误
* RunLoop 暂停导致剩余时间错误

---

# 9. App 生命周期

## App Quit

如果用户退出 Kipless：

```text
立即结束 Session
↓
释放全部 assertion
↓
退出
```

不能让 assertion 在退出后继续存在。

---

## App Relaunch

重新启动后：

```text
Inactive
```

v1.0 不恢复之前 Session。

---

## App Crash

依赖 macOS assertion 生命周期保证进程结束后 assertion 被释放。

同时在应用内部确保：

* assertion ID 不泄漏
* assertion 创建与释放成对
* SessionManager 不保留无效状态

---

# 10. Menu Bar

Kipless 是 Menu Bar App。

默认：

```text
不显示 Dock 图标
```

点击菜单栏图标：

```text
显示 Popover
```

不采用传统菜单作为主要 UI。

---

# 11. Popover

v1.0 Popover 保持非常简单。

Inactive 状态：

```text
Kipless

○ Inactive

Mode
[ System ]
[ Display ]

Duration
[ 30 min ▼ ]

[ Start ]
```

Active 状态：

```text
Kipless

● Active

System awake

42 min remaining

[ Stop ]
```

无限期状态：

```text
Kipless

● Active

System awake
Until stopped

[ Stop ]
```

---

# 12. Menu Bar 状态

Menu Bar 图标至少需要表达：

```text
Inactive
Active
```

不要求 v1.0 显示复杂动画。

菜单栏图标设计原则：

* 简单
* 单色
* Template Image
* 在 Light / Dark Mode 下都清晰
* Active / Inactive 状态明显不同

避免过度使用：

* 月亮
* 床
* 睡眠追踪类视觉元素

Kipless 是系统工具，不是睡眠健康 App。

---

# 13. Settings

v1.0 Settings 只提供：

```text
Launch at Login
```

实现：

```text
SMAppService
```

暂时不加入：

* 默认模式
* 默认 Duration
* 通知设置
* 更新频率
* UI 自定义
* 快捷键
* 高级电源选项

如果用户有实际需求，再进入后续版本。

---

# 14. Power Management 实现

核心实现直接使用 macOS IOKit Power Management API。

不调用：

```text
caffeinate
pmset
shell
Process
```

核心封装：

```text
SleepAssertionManager
```

职责：

```text
createSystemAssertion()
createDisplayAssertion()
releaseAssertion()
```

内部保存：

```text
IOPMAssertionID
```

原则：

* UI 不直接调用 IOKit
* Session 层不关心 assertion API 细节
* assertion 创建失败必须返回错误
* assertion 释放必须幂等
* 禁止 assertion 泄漏

---

# 15. 推荐架构

```text
KiplessApp
│
├── AppState
│
├── WakeSessionManager
│   ├── start()
│   ├── stop()
│   ├── expiration handling
│   └── remaining time
│
├── SleepAssertionManager
│   ├── createSystemAssertion()
│   ├── createDisplayAssertion()
│   └── release()
│
├── MenuBar
│   └── KiplessPopoverView
│
├── Settings
│   └── SettingsView
│
└── Services
    └── LaunchAtLoginService
```

---

# 16. 数据模型

建议：

```swift
enum WakeMode {
    case system
    case display
}
```

```swift
enum WakeDuration {
    case minutes(Int)
    case indefinite
}
```

```swift
struct WakeSession {
    let mode: WakeMode
    let startedAt: Date
    let expiresAt: Date?
}
```

Session 是否 Active：

```text
session != nil
```

避免额外维护重复的：

```text
isActive
```

防止状态不同步。

---

# 17. 状态所有权

整个 App 只允许一个 Session 状态源：

```text
WakeSessionManager
```

Popover：

```text
只观察状态
```

SleepAssertionManager：

```text
只执行底层 assertion
```

UI 不自行维护：

```text
isAwake
remainingTime
currentMode
```

所有状态从 SessionManager 派生。

---

# 18. Timer

Timer 只负责刷新 UI。

例如：

```text
1 second
或
30 seconds
```

剩余时间必须通过：

```text
expiresAt - Date.now
```

计算。

Timer 不能作为真正的 Session 生命周期依据。

---

# 19. 错误处理

可能错误：

```text
Failed to create power assertion
```

如果 assertion 创建失败：

```text
Session 不进入 Active
```

Popover 显示简单错误。

不要：

* 弹系统级连续 Alert
* 重复弹窗
* 静默假装成功

Stop 必须始终可以执行。

---

# 20. Notifications

v1.0 暂时不做通知。

Session 到期后：

```text
直接恢复 Inactive
```

后续如果有需求，可以加入：

```text
Wake session finished
```

但不属于 v1.0 必需范围。

---

# 21. 更新策略

v1.0：

```text
不自动检查更新
```

不在启动时联网。

不因更新服务器不可达弹错误。

后续可以加入：

```text
Check for Updates…
```

以及 Sparkle。

但默认仍应保持安静。

---

# 22. 网络与隐私

Kipless 核心功能完全离线。

v1.0：

```text
No Account
No Analytics
No Telemetry
No Crash Upload
No Tracking
No Cloud
```

不需要服务器。

不采集：

* Mac 型号
* 系统版本统计
* Session 使用情况
* 设备 ID
* IP 地址
* 用户行为

---

# 23. 本地化

v1.0：

```text
English only
```

原因：

* UI 文本非常少
* 初期迭代速度更重要
* 后续本地化成本低

后续可增加：

```text
Chinese
Japanese
```

---

# 24. 开源策略

License：

```text
MPL-2.0
```

仓库：

```text
ShiinaLabs/Kipless
```

公开：

* Source code
* Issues
* Pull Requests
* Releases

README 中不使用竞品对比作为产品定位。

不要使用：

```text
Alternative to ...
Replacement for ...
Like X but ...
```

Kipless 应独立描述自己的功能。

---

# 25. 分发

v1.0 主要分发渠道：

```text
GitHub Releases
```

发布格式：

```text
Kipless-x.y.z.dmg
```

App 使用：

```text
Developer ID Application
Hardened Runtime
Apple Notarization
```

用户正常下载安装，不要求关闭 Gatekeeper。

---

# 26. Homebrew

Homebrew Cask：

```text
v1.0 发布后再考虑
```

不是第一阶段阻塞项。

后续目标：

```bash
brew install --cask kipless
```

---

# 27. Mac App Store

v1.0：

```text
不进入 Mac App Store
```

原因：

* 第一版优先降低发布复杂度
* GitHub Releases 更适合开源工具
* 可以快速迭代
* 不需要处理商店元数据和审核

以后如果有实际需求，再单独评估。

---

# 28. Release 文件

建议：

```text
Kipless/
├── Kipless/
├── KiplessTests/
├── Assets/
├── docs/
│   └── plan.md
├── README.md
├── LICENSE
├── CHANGELOG.md
└── .github/
    └── workflows/
        └── release.yml
```

---

# 29. GitHub README 最低内容

README 至少包含：

```text
Kipless
简介
Features
Requirements
Installation
Build
Privacy
License
```

Features：

```text
• Keep your Mac awake
• Keep your display awake
• Timed wake sessions
• Lightweight menu bar interface
• Fully offline
```

---

# 30. v1.0 明确不做

以下全部不进入 v1.0：

```text
Custom duration
App-based rules
CPU-based rules
Network-based rules
Download detection
Power source rules
Battery percentage rules
Schedule
Profiles
Automation editor
Shortcuts
AppleScript
CLI
Global hotkeys
Sleep history
Usage statistics
Charts
Energy statistics
Notifications
Cloud Sync
iCloud
Account system
Remote control
iPhone companion
Menu bar timer text
Custom themes
Advanced icon customization
AI
```

原则：

> 没有明确需求，不提前建设。

---

# 31. 第一阶段：工程初始化

目标：

建立最小可运行 macOS Menu Bar App。

任务：

```text
[ ] 创建 ShiinaLabs/Kipless
[ ] 添加 MPL-2.0 LICENSE
[ ] 创建 Xcode Project
[ ] Bundle ID = com.kaoru.kipless
[ ] Deployment Target = macOS 14
[ ] 配置 MenuBarExtra
[ ] 隐藏 Dock Icon
[ ] 创建基础 Popover
[ ] 加入基础 App 图标
```

完成标准：

```text
App 可以启动
Menu Bar 图标正常显示
点击可以打开 Popover
App 可以正常退出
```

---

# 32. 第二阶段：Assertion 核心

创建：

```text
SleepAssertionManager
```

完成：

```text
[ ] System assertion
[ ] Display assertion
[ ] Assertion release
[ ] Error handling
[ ] assertion 生命周期保护
```

测试：

```text
[ ] System 模式下显示器可以正常关闭
[ ] System 模式下 Mac 不因 Idle 自动睡眠
[ ] Display 模式下屏幕保持亮
[ ] Stop 后系统恢复正常
[ ] Quit 后恢复正常
```

---

# 33. 第三阶段：Wake Session

创建：

```text
WakeSessionManager
```

实现：

```text
[ ] start(mode:duration:)
[ ] stop()
[ ] expiresAt
[ ] remainingTime
[ ] expiration handling
```

测试：

```text
[ ] 15 分钟 Session
[ ] 30 分钟 Session
[ ] 1 小时 Session
[ ] 2 小时 Session
[ ] 无限 Session
[ ] 到期自动停止
[ ] 重复 Start 不产生多个 assertion
```

---

# 34. 第四阶段：Popover UI

实现 Inactive：

```text
Status
Mode
Duration
Start
```

实现 Active：

```text
Status
Mode
Remaining Time
Stop
```

完成：

```text
[ ] System / Display 选择
[ ] Duration 选择
[ ] Start
[ ] Stop
[ ] Active 状态
[ ] Remaining Time
[ ] 无限期显示
```

---

# 35. 第五阶段：Launch at Login

实现：

```text
SMAppService
```

Settings：

```text
Launch at Login
```

完成：

```text
[ ] Settings Window
[ ] Launch at Login toggle
[ ] 状态正确同步
```

---

# 36. 第六阶段：测试

重点测试以下边界。

## Session

```text
[ ] 快速 Start → Stop
[ ] 连续 Start / Stop
[ ] System → Display
[ ] Display → System
[ ] 定时到期
[ ] 无限期
```

## App 生命周期

```text
[ ] Quit while active
[ ] Relaunch
[ ] macOS logout
[ ] App crash
```

## 系统行为

```text
[ ] Screen lock
[ ] Display idle
[ ] System idle
[ ] Wake from sleep
[ ] External display
[ ] Battery
[ ] AC power
```

## 长时间稳定性

```text
[ ] 运行 8 小时
[ ] 运行 24 小时
[ ] 多次 Session
[ ] 无 assertion 泄漏
[ ] CPU 接近 idle
```

---

# 37. 第七阶段：发布准备

完成：

```text
[ ] App icon
[ ] README
[ ] LICENSE
[ ] CHANGELOG
[ ] Release Notes
[ ] Developer ID signing
[ ] Hardened Runtime
[ ] Notarization
[ ] DMG
```

验证：

```bash
codesign
spctl
```

并在一台未安装开发证书的 Mac 上实际安装测试。

---

# 38. v1.0 Release Checklist

功能：

```text
[ ] System Awake 稳定
[ ] Display Awake 稳定
[ ] Duration 正常
[ ] Infinite 正常
[ ] Stop 正常
[ ] Quit 正常
```

UI：

```text
[ ] Popover 状态正确
[ ] Light Mode
[ ] Dark Mode
[ ] 菜单栏图标清晰
```

系统：

```text
[ ] 不需要管理员权限
[ ] 不修改 pmset
[ ] 不要求额外隐私权限
[ ] 无 assertion 泄漏
```

发布：

```text
[ ] Signed
[ ] Notarized
[ ] DMG 可安装
[ ] Gatekeeper 正常
[ ] GitHub Release 正常
```

---

# 39. v1.0 完成定义

只有满足以下条件，Kipless 1.0 才算完成：

1. System Awake 可以可靠阻止 Idle System Sleep。
2. Display Awake 可以可靠保持显示器唤醒。
3. Timed Session 到期后可靠释放 assertion。
4. Stop 后立即恢复正常系统行为。
5. Quit 后立即恢复正常系统行为。
6. Popover 始终正确显示当前状态。
7. 长时间运行不存在 assertion 泄漏。
8. App 不需要管理员权限。
9. App 不需要额外敏感权限。
10. App 离线时全部核心功能正常。
11. CPU 和内存占用足够低。
12. GitHub 发布版本经过 Developer ID 签名和 Apple notarization。

---

# 40. v1.1 以后再考虑

只有根据真实使用反馈决定。

可能方向：

```text
Custom Duration
Keyboard Shortcut
Session completion notification
Remember last used mode
Remember last used duration
Check for Updates
Sparkle
Homebrew Cask
Shortcuts
CLI
Automation rules
```

不提前承诺 Roadmap。

---

# 41. 开发原则

整个 v1.0 开发过程中遵循：

> 优先保证一件事情做得可靠，而不是增加更多功能。

任何新功能进入 v1.0 前，都问三个问题：

1. 它是否属于睡眠控制的核心路径？
2. 没有它，Kipless 是否无法正常完成主要任务？
3. 它是否值得增加额外状态、UI 和维护成本？

如果答案不是明确的「是」，推迟到后续版本。

Kipless 1.0 的目标不是成为完整的 macOS 电源管理器。

它只需要成为一个可靠、安静、简单的睡眠控制工具。
