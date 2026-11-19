# 当前发布范围的开源声明检查

日期：2026-11-19；版本：窗匣 0.20.0。范围是当前源码、实际构建的 CardinalBridge 锁定依赖和本次 App，不追溯认定全部历史版本都合规。

## 已处理

| 项目 | 检查及处理 |
|---|---|
| 主项目 | 所有者明确选择 MIT；新增根目录 LICENSE、授权范围和 App 内的主项目许可副本。第三方版权不被替换。 |
| Cardinal | 保留原始 MIT 和上游提交；已有本地修订清单保留，修正 UPSTREAM 中“未修改”的过期描述。9 个实际引用的本地引擎组件以原始根许可及修改说明覆盖。 |
| LRUCache | 保留源码头、Nick Lockwood MIT 全文、1.3.0 版本和提交来源。 |
| Amethyst | 保留 Ian Ynda-Hummel MIT 全文和改编范围；补入总声明，避免只有独立文件而摘要漏项。 |
| 文件图标 | 旧图标库有混合来源且缺少所选素材逐项授权说明；按所有者确认，当前源码与 App 移除旧图标，改用 9 个 Lucide SVG，保留完整 ISC 和 Feather MIT 声明及 SHA-256 来源快照。39 个衍生 PNG 的配色和扩展名标签由本项目离线生成。 |
| Rust 注册表依赖 | 与实际 CardinalBridge/Cargo.lock 逐项核对 104 包；保留许可证及附文，补齐 linux-raw-sys、rustix、unicode-normalization 的 3 份 COPYRIGHT。保留多重许可选择和 Unicode 附加许可，没有把所有依赖统一改成 MIT。 |
| typed-num | crate 声明 WTFPL 却没有独立 LICENSE；保留来源说明，并附标准 WTFPL 文本，明确标准文本作者不等于 crate 作者。 |
| Rust 标准库 | 锁定 Cargo 包以外另行保留实际工具链 nightly-2025-12-11 的官方 COPYRIGHT-library.html、纯文本展示和相关许可文本，覆盖标准库的版权及额外例外。文档包含多平台条目，并非所有条目都链接到 macOS。 |
| 二进制分发 | App 打包相同许可与清单，菜单内新增“开源软件声明”并可查看全文；打包后逐文件核对哈希。 |
| 后续升级 | 构建前离线检查 Cargo.lock、原始 SVG、PNG、许可和版权附文。新增/改变依赖不能仅保留旧清单。 |

## 发布内容

- 当前主项目许可：MIT；准确范围见 LICENSE-SCOPE.md。
- 第三方：4 个直接项目、104 个 Rust 注册表包，另含 Rust 标准库声明；原文及清单在 Licenses/。
- GitHub 源码 ZIP 使用目录白名单：包含源代码、资源、Vendored 源码、锁文件、许可证、构建脚本和必要说明；排除本机配置、工作记录、截图、缓存、预编译引擎、旧 App、安装备份和凭据文件。
- GitHub 导出再运行许可检查，并检查明显凭据标记及开发者主目录路径。检查源代码包不等于扫描用户个人目录。

## 结论与边界

当前打包范围的许可文本、署名和附文检查已通过；发布应使用本轮源码包及 App 包，保留其中全部声明。MIT 不是“无需署名”，也不能将第三方组件改称自己的原创作品。

这是工程层面的来源与分发文件核对，不是法律意见或对一切使用方式的保证。它不能独立证明每位上游作者的全部权利链，也不自动授予商标、肖像或其他平台权利；未来新增素材/代码需重新检查。

## 核对依据

- [GitHub：仓库许可说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
- [MIT 条件](https://choosealicense.com/licenses/mit/)
- [Lucide 原始 ISC/MIT 许可](https://github.com/lucide-icons/lucide/blob/main/LICENSE)
- [Amethyst 原始 MIT](https://github.com/ianyh/Amethyst/blob/development/LICENSE.md)
- [Rust 标准库分发声明说明](https://github.com/rust-lang/rust/blob/main/COPYRIGHT)
- [SPDX WTFPL 标准文本](https://spdx.org/licenses/WTFPL.html)

当前源码中的研究引用（如 Nuke、TCA、DockDoor、Ghostty 以及设计参考网站）不作为已链接库列入运行依赖；实际复制或改编的组件仍按上述明确记录保留其许可。Apple 系统框架、字体和系统符号由系统提供，本源码包不重新打包 Apple Music 图片或其他应用图标。
