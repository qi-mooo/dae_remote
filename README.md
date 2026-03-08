# DAE Remote (iOS)

基于 SwiftUI 的 OpenWrt `luci-app-dae` 控制端，使用 `/ubus` JSON-RPC。

## 已实现功能

- 路由器 JSON-RPC 登录（`session.login`）
- 状态读取（`uci.get` + `file.exec /etc/init.d/dae status` + 内存读取）
- 一键启用/禁用 DAE（`uci.set` + `uci.commit` + start/stop）
- 启动/停止/热重载服务（`file.exec`）
- 读取/编辑/保存以下配置文件（`file.read` / `file.write`）：
  - `/etc/dae/config.dae`
  - `/etc/dae/config.d/dns.dae`
  - `/etc/dae/config.d/node.dae`
  - `/etc/dae/config.d/route.dae`
- 液态玻璃风格 UI（`ultraThinMaterial` + 渐变流体背景）

## 运行

1. 生成工程：
   ```bash
   xcodegen generate
   ```
2. 打开 `DAERemote.xcodeproj`，选择模拟器或真机运行。
3. 在 App 里填路由器地址（如 `https://192.168.1.1`）、用户名和密码后连接。

## OpenWrt 侧要求

- 已安装并运行 `luci-app-dae` + `rpcd`
- 登录用户对 `uci/file` 有对应权限（使用 `root` 最直接）
- 若使用自签名证书，可在 App 中开启“允许自签名 TLS”

## 工程结构

- `project.yml`: xcodegen 配置
- `DAERemoteApp/Networking/OpenWrtRPCClient.swift`: JSON-RPC 客户端
- `DAERemoteApp/ViewModels/AppModel.swift`: 业务状态与操作
- `DAERemoteApp/Views/ContentView.swift`: 主界面与液态玻璃视图
