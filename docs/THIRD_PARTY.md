# 第三方组件与素材

SpineSaver 的许可证见仓库根目录的 [LICENSE](../LICENSE)（MIT）。

## 代码依赖

本项目没有第三方代码依赖。`Package.swift` 只声明内部 target 之间的依赖，仓库中没有 `Package.resolved`，也没有任何 Swift Package、CocoaPods、Carthage 或 npm 依赖。

链接的框架全部由 Apple 随 macOS 提供：

- AppKit
- SwiftUI
- Charts
- UserNotifications
- ServiceManagement
- CoreGraphics
- UniformTypeIdentifiers

## 图标与字体

- 界面图标使用 Apple 的 SF Symbols（`figure.walk`、`figure.flexibility`、`cup.and.saucer.fill`、`toilet.fill`、`eye.fill`、`lungs.fill`）。它们通过 `Image(systemName:)` 在运行时调用，仓库中不包含任何符号的导出文件。
- SF Symbols 的使用遵循 Apple 的 SF Symbols 许可：只在面向 Apple 平台的应用程序界面中使用。不得把符号抽取为独立图片素材再分发，也不得用于 logo 或商标。
- 文本使用系统字体，仓库中不包含字体文件。
- 仓库中不包含任何第三方图片。

## 如果你要再分发

- 保留 `LICENSE` 中的版权与许可声明。
- 不要把你自己的截图、QA 证据或本机配置一并发布。
- 构建产物未公证，详见 README 的"打包 DMG"一节。
