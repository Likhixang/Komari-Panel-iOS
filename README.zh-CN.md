# Monitor Panel iOS

[English](README.md) | **简体中文** | [繁體中文](README.zh-TW.md) | [한국어](README.ko.md) | [日本語](README.ja.md)

一款适用于 iPhone 和 iPad 的原生服务器监控应用。统一接入 Komari、哪吒和 DStatus 面板，随时查看服务器运行状态，并在手机上管理 Komari 节点。

基于 SwiftUI 构建，支持 iOS 16 及以上系统，在 iOS 26 上呈现 Liquid Glass 界面。

## 界面预览

<p align="center">
  <img src="docs/screenshots/zh-Hans-preview.png" width="620" alt="总览与节点详情">
</p>

## 核心功能

- **多后端接入** — 支持 Komari 监控与管理，以及哪吒 V1、哪吒 V0 和 DStatus 公开面板的只读监控。
- **服务器总览** — 集中查看节点状态、CPU、内存、磁盘、流量、实时网速及后端提供的延迟指标。
- **节点详情** — 查看硬件信息与历史指标，平滑切换卡片和详情页面。
- **Komari 管理** — 编辑节点、管理 Ping 任务和告警、确认执行远程命令、查看审计日志。
- **个性化设置** — 搜索、排序和隐藏节点，自选深浅色主题与强调色。
- **多语言界面** — 支持简体中文、繁体中文、English、日本語和한국어。
- **直连与隐私** — 凭据保存在 iOS Keychain，默认使用 HTTPS，无中转服务或统计追踪 SDK。

## 下载与安装

需要 **iOS / iPadOS 16.0 或更高版本**。

1. 从 [Releases](https://github.com/Likhixang/Monitor-Panel-iOS/releases/latest) 下载 `Monitor-Panel-iOS-unsigned.ipa`。
2. 使用 SideStore、AltStore 或自己的签名证书进行签名安装。
3. 打开 **面板 → 添加面板**，选择后端并填写地址和凭据。DStatus 公开面板无需 API key。

## 本地构建

需要 **macOS、Xcode 26 和 XcodeGen**，无第三方运行时依赖。

```sh
brew install xcodegen
xcodegen generate
open KomariPanel.xcodeproj
```

如需安装到设备，请在 Xcode 中选择自己的签名团队并启用代码签名。
