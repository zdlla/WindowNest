# 窗匣 WindowNest

macOS 原生窗口、应用与桌面文件夹入口，使用 SwiftUI/AppKit。文件全局查找由本机 Cardinal Rust helper 提供。当前审查版本：0.20.1。

**[下载最新正式版](https://github.com/zdlla/WindowNest/releases/latest)**

## 更新与文件盒

设置提供检查更新、每日自动提醒与下载并更新。更新只替换 App，配置、主题、文件盒书签和多屏布局保存在本机独立目录。更新需访问 GitHub 获取公开版本信息；不会上传文件、目录、索引或配置。签名清单通过后才接受安装包。

文件夹单击在文件盒内进入，支持返回和路径导航；文件单击预览，右键可重命名、用默认应用编辑或打开。可在当前目录新建文件夹并拖入移动。

## 构建

要求 macOS 14 或更新版本、Xcode Command Line Tools、Rust 的 `nightly-2025-12-11` 工具链，以及 arm64/x86_64 macOS 目标。首次构建会从包注册表下载锁定依赖；应用运行时不依赖图标 CDN。

```sh
rustup toolchain install nightly-2025-12-11
rustup target add aarch64-apple-darwin x86_64-apple-darwin --toolchain nightly-2025-12-11
export WINDOW_NEST_BUILD_DIR="$PWD/.build"
python3 Scripts/check_licenses.py
bash build.sh
```

生成 `窗匣.app`，默认使用本地 ad-hoc hardened runtime 签名。公开二进制发行的 Developer ID、公证及权限说明见 `SECURITY.md`。最低部署版本和构建 SDK 以脚本为准，推荐 macOS 26 SDK。

## 第三方代码与图标

Cardinal、LRUCache、Amethyst 的注明改编部分和 Lucide 图标均保留完整许可证。104 个 Rust 注册表依赖的版本、来源、许可选择和声明文件见 [第三方总声明](Licenses/THIRD_PARTY_NOTICES.md) 与 [机器可读清单](Licenses/DEPENDENCIES.json)。自有代码的主许可状态见 [授权范围](LICENSE-SCOPE.md)，不能把所有第三方文件重新声称为自己的作品。

```sh
python3 Scripts/check_licenses.py --bundle 窗匣.app
```

依赖锁定图、图标来源或声明文件改变时，检查会阻止构建，需重新核对。完整审查边界及发布操作见 [GitHub 发布说明](GITHUB_RELEASE.md) 与 [审查记录](OPEN_SOURCE_AUDIT.md)。

运行时文件和偏好保存在本机；桌面文件盒只在用户选定目录后显示其内容。源码发布包不包含任何目录清单、用户配置、个人文档、屏幕截图、凭据或旧 App 副本。
