# FlClash Tailnet

基于 [FlClash-Patched](https://github.com/chenx-dust/FlClash-Patched) 的 Android 自用开发版。
上游基线：`8c316de79dba6d7e022e47c396d6c4d711364993`；原项目为 [FlClash](https://github.com/chen08209/FlClash)。沿用原有 GPL-3.0 许可与作者署名。

## 使用

包名为 `com.follow.clash.dev`，使用 2026-10-31 自用开发版的同一签名。
覆盖安装该开发版可保留其私有目录中的配置和 Tailscale 登录信息。
官方版 `com.follow.clash` 与此包相互独立。

使用现有含 `type: tailscale` 的配置启动 FlClash，然后打开底部「组网」。
页面在只有 Tailscale 出站时显示标题「Tailscale」。点击出站名称展开登录信息和设备列表。
右侧开关控制真实客户端的连接；暂停会阻止该出站的 TCP、UDP 和 DNS 请求，保留账号。
暂停状态记录在原 Tailscale state-dir 内，重载配置和重启后继续生效。
账号退出与连接暂停是两个独立操作。

本版本不会自动导入任何订阅、节点密钥或个人网络配置。已有分流规则继续决定流量去向。
Wi-Fi／蜂窝网络切换修复沿用 `github.com/YuliZheng/tailscale` 的固定版本。

## 构建与验证

`git submodule update --init --recursive`

`flutter pub get`

`dart setup.dart android --arch arm64 --env stable -v`

Android 打包前运行静态分析、Tailscale Go 测试、连接开关与导航等 Flutter 测试。
验证记录和构建时的格式调整补丁保存在 `dist/`。
`core/Clash.Meta` 是兼容仓库既有 Android 构建流程的符号链接，实际内核源码为 `core/mihomo`。
