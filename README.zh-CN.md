<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/lockup-on-dark.png">
    <img src="assets/brand/lockup-on-light.png" alt="RestBar" width="460">
  </picture>
</p>

<p align="center"><strong>Agent 跑着时，别让 Mac 睡</strong></p>

<p align="center"><a href="README.md">English</a></p>

你让 Claude Code 或 Codex 跑一个长任务，人走开了，Mac 却在半路睡着了。RestBar 是一个原生菜单栏小工具，专门解决这件事：它能发现 Agent 正在工作，让 Mac 保持唤醒，合上盖子也行，活干完了再恢复休眠。

```sh
brew install --cask noxr3/tap/restbar
```

不需要账号，不联网，不收集数据，没有第三方依赖。整个应用约 1300 行 Swift，一个下午就能读完。

RestBar 跟随系统语言：英文、简体中文或繁体中文，其他语言显示英文。

| 待机 | 唤醒中 |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/zh-Hans/panel-resting-dark.png"><img src="assets/screenshots/zh-Hans/panel-resting-light.png" alt="RestBar 待机时的面板" width="340"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/zh-Hans/panel-awake-dark.png"><img src="assets/screenshots/zh-Hans/panel-awake-light.png" alt="RestBar 保持唤醒时的面板" width="340"></picture> |

## 功能

- **跟着 Agent 走**：支持 Claude Code、Codex、Gemini CLI、Aider、Cursor Agent、OpenCode、Goose、Amp、Droid、Crush、Cline 和 Qwen Code。Agent 或它启动的程序在占用 CPU 就算工作中，之后再保持十分钟，因为等模型回复时看起来是空闲的。只是开着、什么都没做的会话不会让 Mac 一直醒着。
- **合盖继续跑**：需要你主动打开。
- **自动停止**：可选电量到 20% 时、拔掉电源时，或你设定的时间到了。
- **诊断**：查看 Agent、其他应用和系统休眠策略。
- **基础功能**：手动保持唤醒、屏幕常亮、关闭屏幕、立即休眠，齿轮菜单里还有低电量模式。

## 安装

**Homebrew**

```sh
brew install --cask noxr3/tap/restbar
```

**终端一行命令**

```sh
curl -fsSL https://raw.githubusercontent.com/Noxr3/RestBar/main/install.sh | bash
```

脚本会校验下载文件的校验和、签名和 Apple 公证。想先看内容可以[读一遍脚本](install.sh)。

**下载安装包**

从[最新版本](https://github.com/Noxr3/RestBar/releases/latest)下载 `RestBar.dmg`，打开后把 RestBar 拖进“应用程序”。

**从源码构建**

```sh
git clone https://github.com/Noxr3/RestBar.git
cd RestBar
bash build.sh
open dist/RestBar.app
```

需要 macOS 13 或更新版本。构建产物同时支持 Apple Silicon 和 Intel。点击菜单栏的月亮打开面板，右键可以快速操作。

### 看不到图标？

RestBar 没有窗口。菜单栏放满时，macOS 会把新图标藏到刘海后面，而且没有任何提示，所以可能应用已经在运行，却找不到地方点。按住 ⌘ 拖动其他菜单栏图标腾出位置，或者退出一个不需要的应用。

## 使用须知

- **保持唤醒用的是 macOS 的临时电源请求**，到时间或应用退出时就会释放，应用崩溃也一样。关闭面板不会结束正在进行的唤醒。
- **默认登录时启动**。第一次从“应用程序”文件夹打开时，RestBar 会把自己加入登录项，macOS 会提示你。在齿轮菜单里关闭后不会再自动开启。
- **RestBar 只释放自己的请求**。其他应用可能仍在阻止休眠，可以在“诊断”里查看。
- **不包含**：充电上限、风扇控制、整机功耗估算。

### 合盖运行

无论应用怎么请求，macOS 合盖都会休眠，所以这个功能要用系统设置 `pmset disablesleep`。默认关闭，由你主动打开。具体会发生这些事：

- **第一次打开时**，macOS 会询问一次密码，用来安装 `/etc/sudoers.d/restbar`。这个文件只允许你的账户免密码运行 `pmset -a disablesleep 0` 和 `pmset -a disablesleep 1`，这样你不在电脑前时 RestBar 也能恢复休眠。随时可以在齿轮菜单里移除。
- **休眠会自动恢复**：保持唤醒停止时、应用退出时都会恢复；应用崩溃或被强制退出时，由一个只在本次会话期间存在的小监视进程恢复；重启后，RestBar 下次启动时恢复。
- **会自动停止**：电量到 20% 或 macOS 报告机器过热时，无论其他选项怎么设都会停。不要把运行中的 Mac 放进包里：合盖后散热变差，也不会有任何东西提醒你它变热了。

## Agent 检测

RestBar 每十秒读一次进程列表：进程名、解释器运行的脚本和 CPU 占用。这些信息不保存，也不发送到任何地方。这是一种估算：Agent 静默超过十分钟会被当作已结束，RestBar 不认识的 Agent 也不会被发现。想添加新的 Agent，请看 `Sources/AgentWatch.swift` 里的 `AgentDetector`。

## 项目状态

RestBar 还处于早期。自动检查全部通过，但以下流程仍需要有人在各 macOS 版本上实际试过：合盖运行、管理员修改、立即休眠、关闭屏幕、登录时启动。Intel 版本可以编译，但还没在 Intel Mac 上试过。

开发说明、测试方法和源码结构见[英文说明](README.md#develop)。参与贡献请看 [CONTRIBUTING.md](CONTRIBUTING.md)，报告安全问题请看 [SECURITY.md](SECURITY.md)，视觉与文案规范见 [docs/BRAND.md](docs/BRAND.md)。

## 许可证

[MIT](LICENSE)
