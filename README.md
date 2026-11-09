# 无屏设备如何登录需要网页认证的 Wi-Fi？

用树莓派临时采用本人无屏设备的 Wi-Fi MAC，由本人完成一次 Portal 网页认证，再观察目标设备能否继承认证状态。

> **v0.3.1 · 实验性项目。** 原始材料记录了 Windows SSH 连接树莓派的用户反馈；本版通过 Shell 语法、ShellCheck 与离线回归检查。**无线 MAC 切换、真实 Portal 登录、目标设备继承认证仍待树莓派实机验证。**

**入口：** [完整实操教程](TUTORIAL.md) · [Windows / SSH / VNC 连接指南](docs/connection-methods.md) · [下载 v0.3.1](https://github.com/Xplore-LAB/portal-mac-experiment/releases/tag/v0.3.1) · [博客阅读版](https://xplore-lab.github.io/2026/11/09/portal-mac-experiment/)

## 适用条件

- 本人或明确获授权的设备与账号，且网络管理方允许这项兼容性实验。
- 使用 NetworkManager 的 Linux / Raspberry Pi OS，具备 Bash 4+、`nmcli`、`ip`、`sudo` 及基础系统工具。
- Wi-Fi 无需密码即可关联，随后通过网页 Portal 登录；本版测试链路要求 IPv4。WPA 密码网络、802.1X / WPA-Enterprise 不在脚本支持范围。
- 具备本地终端或独立有线 SSH / VNC 管理链路。**不能通过即将修改的无线网卡维持唯一管理连接。**
- 目标设备完全离线，同一时刻只有一台设备使用该 MAC。

Portal 可能同时绑定 MAC、IP、接入位置或会话。树莓派认证成功与目标设备继承成功，需要分别验证；项目不承诺成功率、长期联网或自动续期。

## 快速开始

从 Release 下载 `portal-mac-experiment-v0.3.1.zip`，在树莓派解压：

```bash
unzip portal-mac-experiment-v0.3.1.zip
cd portal-mac-experiment
bash quick-start.sh --check
bash quick-start.sh
```

也可获取源码：

```bash
git clone https://github.com/Xplore-LAB/portal-mac-experiment.git
cd portal-mac-experiment
bash quick-start.sh --check
```

使用普通用户运行脚本；需要权限时由脚本调用 `sudo nmcli`，不要给整段引导额外套 `sudo`，以免丢失 SSH 环境信息。

首次运行填写 SSID 和目标 MAC，后续只需填写 MAC；仍需完成确认和本人网页登录。支持 `aa:bb:cc:dd:ee:ff`、`aa-bb-cc-dd-ee-ff`、`aabbccddeeff` 三种格式。

```bash
bash quick-start.sh --setup        # 更换本机保存的 SSID
bash setup-launcher.sh             # 可选：在树莓派图形桌面创建启动入口
WIFI_IF=wlan1 bash quick-start.sh  # 按实际无线接口名调整
```

引导依次执行：检查管理链路 → 创建临时配置 → 核验实际 MAC、IPv4 与出口 → 本人登录 Portal → 清理测试连接。没有桌面时，先阅读[连接指南](docs/connection-methods.md)，准备经管理方许可的认证方式。

## 独立有线管理链路

Windows 与树莓派网线直连时，可使用 Windows `192.168.88.1/24`、树莓派 `192.168.88.2/24`，管理网线不设置网关或 DNS。先确认该网段与现有网络不冲突。

在树莓派**已有的另一条控制通道**中运行：

```bash
bash scripts/ethernet-management.sh check
bash scripts/ethernet-management.sh prepare
bash scripts/ethernet-management.sh up
```

确认从 Windows 执行 `ssh myuser@192.168.88.2` 能稳定登录后，再切换 Wi-Fi。脚本在创建与启用时都检查网口占用；恢复有线配置时拒绝断开承载当前 SSH 的接口。完整 Windows 设置及回滚见[连接指南](docs/connection-methods.md)。

## 手动执行与清理

```bash
bash scripts/portal-mac.sh check
bash scripts/portal-mac.sh prepare
bash scripts/portal-mac.sh connect
bash scripts/portal-mac.sh status
bash scripts/portal-mac.sh restore
```

`restore` 停止本项目的测试连接并删除对应配置，**不保证驱动立即恢复原 MAC，也不会自动重连原 Wi-Fi**。即使配置已消失，仍需确认无线状态。交接目标设备前，建议将树莓派关机。被强制断电或终止后，应先检查并清理残留状态。

临时 Wi-Fi 配置使用 NetworkManager 的 `save no`，仅驻留内存；NetworkManager 重启后会消失。快速入口在用户配置目录持久保存 SSID；运行时输出和内存配置包含本次 MAC。脚本不收集 Portal 密码，浏览器的 Cookie 和密码保存由浏览器自行管理。不要公开原始终端输出、浏览器资料或个人配置。

## 如何判断结果

| 检查项 | 通过条件 |
|---|---|
| MAC 切换 | `/sys/class/net/<接口>/address` 与目标 MAC 一致 |
| 网络关联 | 测试 Wi-Fi 已连接并有 IPv4 地址 |
| Portal 登录 | 本人完成官方认证，并确认测试流量经测试 Wi-Fi 访问公网 |
| 设备继承 | 树莓派退出后，目标设备无需网页操作即可联网 |
| 重启后有效 | 单独记录设备重启后的联网结果 |

脚本检查到 `1.1.1.1` 的 IPv4 路由，不能替代对 Portal 服务器、浏览器代理、VPN 或 IPv6 路径的核查。使用无默认网关的独立管理链路，并按实际流量确认结果。

用 [experiments/result-template.yaml](experiments/result-template.yaml) 记录**脱敏后的**观测。`null` 表示未测，`false` 表示实测失败；不能将两者混用。

## 本版修正与验证

v0.3.1 修正 MAC 字段的 `nmcli` 转义读取、准备失败时误清理旧配置、有线启用前的占用复查；补充 IPv4 检查、IPv6 SSH 路由识别、全零 MAC / SSID 长度校验，以及桌面入口路径检查。测试 Wi-Fi 配置改为仅驻留内存，恢复动作可重复执行。

开发者离线检查需要 Python 3；安装了 ShellCheck 时也会执行静态检查：

```bash
bash tests/smoke.sh
```

回归测试用替代命令模拟 NetworkManager、路由与失败场景，不修改真实网卡。通过这些检查只说明相应代码路径符合预期；实际驱动、门户和设备兼容性仍需实测。

## 使用与发布

仅开展获得许可的个人设备兼容性实验；不提交真实 MAC、账号、密码、Cookie 或 Token，不部署后台续登、NAT 或未经许可的共享服务。详细约束和异常处理见 [SECURITY.md](SECURITY.md)。

**许可证：尚未指定。** 本次按实验性项目公开代码及教程，保留原材料未指定许可证的状态，不额外添加 MIT / Apache 等授权。贡献或复用前请与维护者确认许可。

## 官方参考

- [NetworkManager：nmcli、输出转义与内存连接配置](https://networkmanager.dev/docs/api/latest/nmcli.html)
- [NetworkManager：Wi-Fi cloned-mac-address](https://networkmanager.dev/docs/api/latest/nm-settings-nmcli.html)
- [Raspberry Pi：初始化与安装](https://www.raspberrypi.com/documentation/computers/getting-started.html)
- [Raspberry Pi：SSH / VNC 远程访问](https://www.raspberrypi.com/documentation/computers/remote-access.html)
