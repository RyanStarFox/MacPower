# MacPower

![License: MIT + Commons Clause](https://img.shields.io/badge/License-MIT%20%2B%20Commons%20Clause-blue.svg) ![LINUX DO](https://img.shields.io/badge/LINUX-DO-FFB003.svg?logo=data:image/svg%2bxml;base64,DQo8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjEwMCIgaGVpZ2h0PSIxMDAiPjxwYXRoIGQ9Ik00Ni44Mi0uMDU1aDYuMjVxMjMuOTY5IDIuMDYyIDM4IDIxLjQyNmM1LjI1OCA3LjY3NiA4LjIxNSAxNi4xNTYgOC44NzUgMjUuNDV2Ni4yNXEtMi4wNjQgMjMuOTY4LTIxLjQzIDM4LTExLjUxMiA3Ljg4NS0yNS40NDUgOC44NzRoLTYuMjVxLTIzLjk3LTIuMDY0LTM4LjAwNC0yMS40M1EuOTcxIDY3LjA1Ni0uMDU0IDUzLjE4di02LjQ3M0MxLjM2MiAzMC43ODEgOC41MDMgMTguMTQ4IDIxLjM3IDguODE3IDI5LjA0NyAzLjU2MiAzNy41MjcuNjA0IDQ2LjgyMS0uMDU2IiBzdHlsZT0ic3Ryb2tlOm5vbmU7ZmlsbC1ydWxlOmV2ZW5vZGQ7ZmlsbDojZWNlY2VjO2ZpbGwtb3BhY2l0eToxIi8+PHBhdGggZD0iTTQ3LjI2NiAyLjk1N3EyMi41My0uNjUgMzcuNzc3IDE1LjczOGE0OS43IDQ5LjcgMCAwIDEgNi44NjcgMTAuMTU3cS00MS45NjQuMjIyLTgzLjkzIDAgOS43NS0xOC42MTYgMzAuMDI0LTI0LjM4N2E2MSA2MSAwIDAgMSA5LjI2Mi0xLjUwOCIgc3R5bGU9InN0cm9rZTpub25lO2ZpbGwtcnVsZTpldmVub2RkO2ZpbGw6IzE5MTkxOTtmaWxsLW9wYWNpdHk6MSIvPjxwYXRoIGQ9Ik03Ljk4IDcwLjkyNmMyNy45NzctLjAzNSA1NS45NTQgMCA4My45My4xMTNRODMuNDI2IDg3LjQ3MyA2Ni4xMyA5NC4wODZxLTE4LjgxIDYuNTQ0LTM2LjgzMi0xLjg5OC0xNC4yMDMtNy4wOS0yMS4zMTctMjEuMjYyIiBzdHlsZT0ic3Ryb2tlOm5vbmU7ZmlsbC1ydWxlOmV2ZW5vZGQ7ZmlsbDojZjlhZjAwO2ZpbGwtb3BhY2l0eToxIi8+PC9zdmc+) ![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white) ![Swift](https://img.shields.io/badge/Swift-6-F05138.svg?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue.svg) ![Release](https://img.shields.io/github/v/release/RyanStarFox/MacPower)

![MacPower](docs/readme/icon.png)

中文 | [English](README.en.md)

MacBook 菜单栏电池监视器。不进 Dock，点开后是 **Liquid Glass** 监控面板：能量流向、系统圆环、续航或充满时间，外观与动效都可自定义。

## 预览


|                                                                       |                                                                                   |                                                                                       |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| ![电池给电脑 · 粒子](docs/readme/flow-discharging.png) **电池 → 电脑** · 粒子      | ![电源给电脑 · 渐变](docs/readme/flow-adapter-hold.png) **电源 → 电脑** · 渐变                 | ![电源和电池给电脑 · 细线 · 高对比](docs/readme/flow-underpowered.png) **电源 + 电池 → 电脑** · 细线 · 高对比 |
| ![电源给电池和电脑 · 滑动](docs/readme/flow-charging.png) **电源 → 电池 + 电脑** · 滑动 | ![电池给电脑 · 柔和 · 细线](docs/readme/flow-discharging-smooth.png) **电池 → 电脑** · 柔和 · 细线 | ![电源给电池和电脑 · 无动效](docs/readme/flow-charging-off.png) **电源 → 电池 + 电脑** · 无动效           |




## 功能

- 菜单栏 Liquid Glass 监控面板（能量流向、电量 / CPU / GPU / 内存圆环、续航或充满时间）
- 高度可自定义：配色预设、图标套装、动效样式、菜单栏电池外观等
- 不进 Dock；可选登录时启动、自动检查更新
- 多语言：简体中文、繁体中文、English、日本語、한국어、Français、Deutsch、Español、Português (Brasil)、Italiano、Русский（设置里可跟随系统或单独切换）



## 安装



### 第一步：下载并安装

从 [Releases](https://github.com/RyanStarFox/MacPower/releases) 下载最新的 `MacPower-*.dmg`，打开后把 **MacPower** 拖进 **应用程序**。

也可以用 Homebrew：

```bash
brew install --cask --no-quarantine ryanstarfox/tap/macpower
```

`--no-quarantine` 是必须的。官方 `homebrew/cask` 不接收这类安装包，这里用的是个人 tap。用这条命令安装时，第二步的拦截通常不会出现，第三步仍然要做。

### 第二步：处理被系统拦住

安装包没有经过 Apple 公证。我没有购买 Apple 开发者账号，个人账号每年 99 美元，所以系统会拦住第一次打开。这不是病毒。MacPower 是开源软件，代码都在仓库里，如果里面有病毒，看源码就能看出来。

双击打开 MacPower。系统会弹出下面这个窗口。点 **完成**，不要点 **移到废纸篓**。方法一和方法二都会先看到它。

![未打开 MacPower.app](docs/install/gatekeeper-zh.png)

接着用方法一允许打开。方法一不行，再用方法二。

#### 方法一：在系统设置里允许打开

打开 **系统设置 → 隐私与安全**，把右边页面拉到「安全性」最下面。看到 **已阻止「MacPower.app」以保护 Mac** 后，点右边的 **仍要打开**，再按提示确认。

![在隐私与安全中仍要打开](docs/install/privacy-zh.png)

#### 方法二：用终端清除隔离

打开「终端」，粘贴下面的命令并回车。输入密码时屏幕不会显示圆点，输完直接回车：

```bash
sudo xattr -rd com.apple.quarantine /Applications/MacPower.app
```

### 第三步：在菜单栏里显示

打开 **系统设置 → 菜单栏**。

- 允许 **MacPower** 在菜单栏中显示，然后从「应用程序」启动。
- 建议关掉系统自带的 **电池**。菜单栏只留 MacPower，避免两个电池图标叠在一起。这一项可以不关。

## 运行要求

- macOS 14 或更高（在 macOS 26+ 上使用 Liquid Glass；14/15 为材质回退）
- 带电池的 Apple 芯片 MacBook



## 从源码编译

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project MacPower.xcodeproj -scheme MacPower -configuration Release -destination 'platform=macOS' build
```

重新制作 Release 磁盘镜像：

```bash
./scripts/make_dmg.sh
```

生成的 `.dmg` 在 `dist/`。

## 发布后同步

GitHub Release 发出去之后，在这台已经登录阿里云盘的 Mac 上再执行一次：

```bash
python3 scripts/sync_latest_release.py
```

同一次会做这三件事：

- 把 GitHub 上的 `main` 和该版本 tag 推到 [Gitee](https://gitee.com/Ryan_LS_Wang/MacPower)，创建对应发行版，并上传 `MacPower-*.dmg`
- 把安装包上传到阿里云盘备份盘 `/软件/MacPower`
- 把安装包上传到百度网盘 `/apps/MacPower/releases/`

Gitee 使用本机 `~/.netrc` 里的 `machine gitee.com`，私人令牌不要写进仓库。这个版本已经同步过时，命令会直接结束。

安装说明是仓库根目录里的固定文件：`如何安装.txt`、`如何安装.md`、`如何安装.html`、`如何安装.docx`，以及英文的 `how2install.txt`、`how2install.md`、`how2install.html`、`how2install.docx`。内容不随版本变化，不随每次 Release 重复上传。

百度的 refresh token 只授权一次。脚本刷新后会把新 token 存回本机，不用每次手动改。第一次，或 token 失效后：

```bash
python3 scripts/set_baidu_refresh_token.py
```

终端会打印授权网址和用户码。在浏览器打开那个网址，登录百度，输入用户码并确认。完成后 token 会写入本机。

## 许可证

本项目采用 MIT License，并附加 Commons Clause。允许免费使用、修改和分发，但不得销售本软件，或通过主要依赖本软件功能的产品或服务获利。详见 [LICENSE](LICENSE)。

---

本开源项目已链接并认可 [LINUX DO 社区](https://linux.do)。