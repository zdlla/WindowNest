# 窗匣 WindowNest

轻量的原生 macOS 窗口、应用与桌面文件盒工具。支持 macOS 14+，提供 Apple Silicon / Intel 通用安装包。

## 下载与更新

**[下载最新正式版](https://github.com/zdlla/WindowNest/releases/latest)**

下载 Release 中的 `WindowNest-版本号-universal.zip`，解压后将“窗匣.app”放进应用程序文件夹。更新时替换 App 即可，本机配置、主题、文件盒绑定、多屏布局及个人文件独立保留。新版设置内也提供“检查更新”和“下载并更新”。

- 公开版本检查每天最多一次，可关闭；不上传文件、目录、索引或设置。
- 更新清单以固定公钥核验签名，安装包另核对 SHA-256；只有用户确认才下载替换。
- 尚未提供 Developer ID 公证，macOS 可能要求确认来源或重新授权；不要关闭系统安全保护。

## 文件盒

目录单击进入内部浏览，支持返回和路径导航；文件单击预览，右键重命名或用默认应用编辑。支持在当前目录新建文件夹及拖入移动。目录位置、大小和主题支持保存，单屏/扩展/镜像分别记忆。

## 源码与许可

当前完整源码以每次 Release 的 `WindowNest-版本号-source.zip` 提供，包含构建脚本、锁定依赖和完整第三方许可证，不含用户数据或预编译引擎。

自有代码采用 MIT，见 [LICENSE](LICENSE) 和 [授权范围](LICENSE-SCOPE.md)。第三方仍保留各自许可，详见 [开源总声明](THIRD_PARTY_NOTICES.md) 与 [核对记录](OPEN_SOURCE_AUDIT.md)。完整原文同时放在源码与 App 的 Licenses 目录，并可从 App 的“开源软件声明”菜单查看。
