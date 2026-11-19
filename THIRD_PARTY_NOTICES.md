# 窗匣 · 第三方开源软件声明

核对日期：2026-11-19。自有代码由所有者选择 MIT，见 WindowNest-MIT.txt；该授权不替换下述第三方许可。下面是当前构建实际包含的第三方代码和图形；各组件保留其原始版权与许可，自有代码的授权不替换这些许可。

| 组件 | 使用范围 | 来源与版本 | 许可全文 |
|---|---|---|---|
| Cardinal | 本机 Rust 文件引擎；9 个工作区组件，含已记录的本地安全修订 | https://github.com/cardisoft/cardinal — 4c50734f9a09d88110f96652b43634b412f79449 | Cardinal-MIT.txt |
| LRUCache | Swift 内存缓存实现 | https://github.com/nicklockwood/LRUCache — 1.3.0 / f0570e943ea4445d258113ba73f50cb2b7e564ac | LRUCache-MIT.txt |
| Amethyst | 窗口键事件适配的改编部分 | https://github.com/ianyh/Amethyst — NativeWindowFocus.swift 所注明的改编 | Amethyst-MIT.txt |
| Lucide | 9 个 SVG 及离线生成的 39 个文件类型 PNG；加入本地配色、底色和扩展名标签 | https://github.com/lucide-icons/lucide — 2026-11-19 内容快照；源码内附 SHA-256 | Lucide-ISC-MIT.txt（含 Feather 的 MIT 声明） |

完整版权、许可、附加 NOTICE/COPYRIGHT 文本位于本目录和 Rust/ 子目录，随源码和 App 一起分发。应用的“开源软件声明”窗口也展示这些全文。不得只保留这份摘要而删除许可原文。

当前版本不再打包旧 File Icon Vectors 图标，因为其上游将部分素材描述为 Creative Commons 或购买授权，没有对所选素材逐项明确；旧版本的许可记录不代表旧包已完成本次核查。

## Rust 标准库

helper 静态链接的 Rust 标准库也保留声明，不能只统计 Cargo.lock。实际工具链为 nightly-2025-12-11；完整官方标准库声明与版权在 RustStandardLibrary/COPYRIGHT-library.html，并提供同内容的纯文本展示及相关标准许可文本。该上游文档覆盖多个目标平台，不表示所有平台专用条目都链接进 macOS helper。

## Rust 间接依赖

下面 104 个注册表包来自 CardinalBridge/Cargo.lock 的完整锁定图，包括构建和平台专用依赖。适用的多重许可按许可文本允许的 MIT 分支使用；Unicode 附加许可仍同时保留。BSD-3-Clause、Zlib、WTFPL 也单独保留，不能把整个依赖图写成“都是 MIT”。详细版本、来源、选择分支、归档校验和及声明文件列表见 DEPENDENCIES.json。

typed-num 的 crate 只声明 WTFPL，未自带独立 LICENSE 文件：保留原始来源说明，附 SPDX 标准 WTFPL 文本；标准文本作者不被写成该 crate 的作者。

| Crate | Version | License expression |
|---|---|---|
| aho-corasick | 1.1.5 | Unlicense OR MIT |
| allocator-api2 | 0.2.21 | MIT OR Apache-2.0 |
| anyhow | 1.0.104 | MIT OR Apache-2.0 |
| base64 | 0.23.1 | MIT OR Apache-2.0 |
| bitflags | 1.3.2 | MIT/Apache-2.0 |
| bitflags | 2.13.2 | MIT OR Apache-2.0 |
| block2 | 0.6.2 | MIT |
| cc | 1.11.0 | MIT OR Apache-2.0 |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 |
| cobs | 0.3.0 | MIT OR Apache-2.0 |
| crossbeam-channel | 0.5.17 | MIT OR Apache-2.0 |
| crossbeam-deque | 0.8.8 | MIT OR Apache-2.0 |
| crossbeam-epoch | 0.9.21 | MIT OR Apache-2.0 |
| crossbeam-utils | 0.8.23 | MIT OR Apache-2.0 |
| defmt | 1.2.0 | MIT OR Apache-2.0 |
| defmt-macros | 1.2.0 | MIT OR Apache-2.0 |
| defmt-parser | 1.1.0 | MIT OR Apache-2.0 |
| deranged | 0.5.9 | MIT OR Apache-2.0 |
| dispatch2 | 0.3.1 | Zlib OR Apache-2.0 OR MIT |
| either | 1.19.0 | MIT OR Apache-2.0 |
| embedded-io | 0.4.0 | MIT OR Apache-2.0 |
| embedded-io | 0.6.1 | MIT OR Apache-2.0 |
| enumn | 0.1.14 | MIT OR Apache-2.0 |
| equivalent | 1.0.3 | Apache-2.0 OR MIT |
| errno | 0.3.14 | MIT OR Apache-2.0 |
| fastrand | 2.5.0 | Apache-2.0 OR MIT |
| find-msvc-tools | 0.1.15 | MIT OR Apache-2.0 |
| foldhash | 0.2.0 | Zlib |
| getrandom | 0.4.3 | MIT OR Apache-2.0 |
| hashbrown | 0.16.1 | MIT OR Apache-2.0 |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 |
| indexmap | 2.14.2 | Apache-2.0 OR MIT |
| itertools | 0.14.0 | MIT OR Apache-2.0 |
| itoa | 1.0.18 | MIT OR Apache-2.0 |
| jiff | 0.2.39 | Unlicense OR MIT |
| jiff-core | 0.1.2 | Unlicense OR MIT |
| jiff-static | 0.2.39 | Unlicense OR MIT |
| jiff-tzdb | 0.1.9 | Unlicense OR MIT |
| jiff-tzdb-platform | 0.1.3 | Unlicense OR MIT |
| jobserver | 0.1.35 | MIT OR Apache-2.0 |
| libc | 0.2.191 | MIT OR Apache-2.0 |
| linux-raw-sys | 0.12.1 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT |
| lock_api | 0.4.14 | MIT OR Apache-2.0 |
| log | 0.4.35 | MIT OR Apache-2.0 |
| memchr | 2.8.3 | Unlicense OR MIT |
| memmap2 | 0.9.12 | MIT OR Apache-2.0 |
| num-conv | 0.2.2 | MIT OR Apache-2.0 |
| objc2 | 0.6.5 | MIT |
| objc2-core-foundation | 0.3.2 | Zlib OR Apache-2.0 OR MIT |
| objc2-core-services | 0.3.2 | Zlib OR Apache-2.0 OR MIT |
| objc2-encode | 4.1.0 | MIT |
| once_cell | 1.21.4 | MIT OR Apache-2.0 |
| parking_lot | 0.12.5 | MIT OR Apache-2.0 |
| parking_lot_core | 0.9.12 | MIT OR Apache-2.0 |
| pin-project-lite | 0.2.17 | Apache-2.0 OR MIT |
| pkg-config | 0.3.34 | MIT OR Apache-2.0 |
| plist | 1.10.3 | MIT |
| portable-atomic | 1.15.0 | Apache-2.0 OR MIT |
| portable-atomic-util | 0.2.8 | Apache-2.0 OR MIT |
| postcard | 1.1.3 | MIT OR Apache-2.0 |
| powerfmt | 0.2.1 | MIT OR Apache-2.0 |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 |
| quick-xml | 0.42.0 | MIT |
| quote | 1.0.47 | MIT OR Apache-2.0 |
| r-efi | 6.0.0 | MIT OR Apache-2.0 OR LGPL-2.1-or-later |
| rayon | 1.12.0 | MIT OR Apache-2.0 |
| rayon-core | 1.13.0 | MIT OR Apache-2.0 |
| redox_syscall | 0.5.18 | MIT |
| regex | 1.13.1 | MIT OR Apache-2.0 |
| regex-automata | 0.4.18 | MIT OR Apache-2.0 |
| regex-syntax | 0.8.11 | MIT OR Apache-2.0 |
| rustc-hash | 2.1.3 | Apache-2.0 OR MIT |
| rustix | 1.1.6 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT |
| scopeguard | 1.2.0 | MIT OR Apache-2.0 |
| serde | 1.0.229 | MIT OR Apache-2.0 |
| serde_core | 1.0.229 | MIT OR Apache-2.0 |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 |
| serde_json | 1.0.154 | MIT OR Apache-2.0 |
| serde_repr | 0.1.21 | MIT OR Apache-2.0 |
| shlex | 2.0.1 | MIT OR Apache-2.0 |
| smallvec | 1.16.4 | MIT OR Apache-2.0 |
| syn | 2.0.119 | MIT OR Apache-2.0 |
| syn | 3.0.9 | MIT OR Apache-2.0 |
| tempfile | 3.27.0 | MIT OR Apache-2.0 |
| thin-vec | 0.2.21 | MIT OR Apache-2.0 |
| thiserror | 2.0.21 | MIT OR Apache-2.0 |
| thiserror-impl | 2.0.21 | MIT OR Apache-2.0 |
| time | 0.3.55 | MIT OR Apache-2.0 |
| time-core | 0.1.9 | MIT OR Apache-2.0 |
| time-macros | 0.2.32 | MIT OR Apache-2.0 |
| tinyvec | 1.13.3 | Zlib OR Apache-2.0 OR MIT |
| tracing | 0.1.44 | MIT |
| tracing-attributes | 0.1.31 | MIT |
| tracing-core | 0.1.36 | MIT |
| typed-num | 0.3.0 | WTFPL |
| unicode-ident | 1.0.27 | (MIT OR Apache-2.0) AND Unicode-3.0 |
| unicode-normalization | 0.1.26 | (MIT OR Apache-2.0) AND Unicode-3.0 |
| windows-link | 0.2.1 | MIT OR Apache-2.0 |
| windows-sys | 0.61.2 | MIT OR Apache-2.0 |
| xattr | 1.7.0 | MIT OR Apache-2.0 |
| zmij | 1.0.23 | MIT |
| zstd | 0.14.3 | BSD-3-Clause |
| zstd-safe | 8.2.0 | BSD-3-Clause |
| zstd-sys | 2.1.2+zstd.1.5.7 | BSD-3-Clause |
