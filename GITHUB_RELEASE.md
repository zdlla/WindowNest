# GitHub 发布说明

1. 使用本次生成的 `窗匣-0.20.1-GitHub源码.zip`，只上传解压后的项目目录。不要直接上传整个开发工作区、work、outputs、安装备份或个人文件。
2. 一起保留 `Licenses/`、`LICENSE-SCOPE.md`、`Vendor/*` 内的原始许可证、来源快照与修改说明。目录名改变时同步修正引用。
3. 发布二进制时使用本轮检查通过的 0.20.1 App ZIP；App 包含相同声明及完整许可文本。不要把旧版 App ZIP 自动当成本轮已核查的发行物。
4. `python3 Scripts/check_licenses.py` 检查锁定依赖、许可附文与图标来源；`--bundle` 额外核对 App 内的原文。依赖改变后需重新运行 Cargo metadata，并人工核对、补齐和更新清单，不要直接关闭检查。
5. 所有者已选择 MIT：一起提交根目录 LICENSE 和 LICENSE-SCOPE.md。主项目允许使用、修改和再分发，须保留版权与许可；第三方仍遵守原许可，不能全部重新标成你的版权。

这是基于当前文件和锁定图的发布准备，不是对所有历史版本、所有使用方式或上游权利链的法律保证。图标商标、第三方软件名称和平台审核要求也不会因附带许可证而自动获得授权。源码包使用通用文件类型图形，不附带第三方应用图标或 Apple Music 截图。


## 后续版本与签名更新

公开仓库：https://github.com/zdlla/WindowNest 。正式版使用 `v版本号` 标签。每次发行提供版本化通用 App ZIP、源码 ZIP、SHA256SUMS.txt、update-manifest.json 和 update-manifest.sig。

清单须以同一发布密钥签名，内容包括仓库、版本、最低系统、包名、SHA-256 和字节数。签名脚本在 Scripts/sign_update.swift；私钥保存在发布者本机，绝不提交。请安全备份私钥，否则已安装版本无法验证未来的新签名。改版之后必须重新检查公开下载、签名、覆盖安装和数据保留。
