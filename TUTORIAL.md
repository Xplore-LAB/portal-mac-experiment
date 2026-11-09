# 无屏智能设备如何登录需要网页认证的 Wi-Fi？树莓派临时 MAC 模拟实验教程

> **项目状态：实验性方案。** 原始材料记录了 Windows 通过 SSH 控制树莓派准备环节的用户反馈；v0.3.1 已通过脚本语法、ShellCheck 和离线回归检查。MAC 临时模拟、Portal 登录以及目标设备能否继承认证仍需实机测试。
>
> **用途边界：** 仅限本人设备、本人账号及网络管理方明确允许的兼容性实验。此项目不提供认证绕过功能，也不支持自动续期或长期保活。

## 一、要完成什么

在学校宿舍、酒店或统一供网的公寓里，你可能遇到过这样的情况：手机连上 Wi-Fi 后，打开网页输入账号或验证码，就可以上网；另一些设备虽然能连上 Wi-Fi，却没有地方打开这个登录网页。这个网页通常就叫 **Portal 认证页**。

本文讨论一个有待实机验证的办法：**让树莓派临时使用目标设备的无线网卡地址（MAC），由本人完成一次网页登录；树莓派退出后，再让目标设备连接，观察它能否直接上网。** 后文会介绍 MAC 怎么查，以及树莓派怎么操作。

### “无屏智能设备”指哪些东西？

它们就在日常生活里，例如：

- **智能音箱：** 用来听在线音乐、查询天气或进行语音问答，通常通过手机 App 设置 Wi-Fi。
- **Wi-Fi 摄像头：** 例如家用室内摄像头、宠物摄像头，需要联网才能使用相应的远程查看功能。
- **扫地机器人：** 连接 Wi-Fi 后，可以使用厂商 App 提供的远程操作、清扫记录等功能。
- **直接连接 Wi-Fi 的智能插座、智能灯泡等：** 用手机 App 设置网络和使用相应的联网功能。

这些产品的共同点是：**能使用网络，却未必有浏览器让你完成上网认证。** 有些产品有小显示屏，但同样无法打开认证网页，也可能遇到这个问题。这里举的是产品类别，具体型号和固件的适用性仍需确认；仅使用蓝牙、或通过网关连接的产品，要按它们实际的联网方式判断。

### 常见应用场景

| 场景 | 可能遇到的问题 |
|---|---|
| 学校宿舍、校园生活区 | 想使用自己的智能音箱等设备，但校园 Wi-Fi 要先在网页中输入学号、账号或验证码。 |
| 长租公寓、员工宿舍 | 房间使用统一提供的 Wi-Fi，手机可以完成网页登录，智能家居设备却没有认证入口。 |
| 酒店、民宿、短住公寓 | 携带自己的联网设备入住，网络要求在网页中填写房号、手机号或确认使用条款。 |
| 共享办公、临时展台 | 经场地方许可演示智能设备，但提供的访客 Wi-Fi 需要通过网页认证。 |

这些是可能遇到同类问题的场景，**能否使用本文方案，要看具体网络和设备**。当前脚本要求 Wi-Fi 本身无需密码即可连接，随后再通过网页认证；需要先输入 Wi-Fi 密码的网络不在本版支持范围内。

如果学校或场地方提供“智能设备登记”“物联网专网”等入口，或设备本身提供酒店、校园网络连接功能，优先使用这些正式方式。[高校设备登记示例](https://it.cornell.edu/wifi/register-device-doesnt-have-browser)和[厂商官方设置示例](https://support.apple.com/guide/homepod/set-up-homepod-apd779d9bb45/homepod)可以帮助理解这两种途径。

### 准备物品

| 物品 | 用来做什么 |
|---|---|
| **一台目标智能设备及其电源** | 例如上面列举的音箱、摄像头、扫地机器人或 Wi-Fi 插座；需要能查到它实际使用的 Wi-Fi MAC。 |
| **一套能正常启动的树莓派** | 包含带 Wi-Fi 的树莓派、匹配的电源和已装系统的存储介质。系统需使用 NetworkManager，后文的 `nmcli` 就是它的命令行工具。 |
| **手机和设备配套 App（按设备需要）** | 用于给设备选择 Wi-Fi、查看设备信息。本文不会代替设备原本的首次联网设置。 |
| **本地操作或电脑远程操作，二选一** | 本地操作准备显示器、键盘，使用图形桌面时配鼠标；远程操作准备电脑和独立网线管理连接，本文以 Windows 为例。电脑没有有线网口时，可按需准备 USB 有线网卡。 |
| **目标网络的信息** | Wi-Fi 名称（SSID）、本人的网页登录账号或其他认证资料，以及网络管理方对这项实验的许可。 |

两套常见组合是：

- **在树莓派旁操作：** 目标设备 + 树莓派完整套件 + 显示器、键盘；用浏览器时配鼠标。
- **在电脑上操作：** 目标设备 + 树莓派完整套件 + 电脑、网线，先按后文建立独立的有线管理连接。

设备需要手机 App 设置 Wi-Fi 时，两种组合都另备手机。已有系统的树莓派可以沿用，不必为这项实验重新购买或重装。

### 开始前再确认两件事

1. **设备本身能连接这个 Wi-Fi。** 核对说明书中的频段要求，例如是否支持目标网络的 2.4 GHz 或 5 GHz；如果设备连 Wi-Fi 这一步就做不到，先解决这个问题。
2. **把“能上网”和“能互相控制”分开测试。** 有些访客网络会让各台设备彼此不可见。即使设备能访问互联网，手机 App 发现设备、投屏或多设备联动仍可能需要另外处理。[Google 官方说明也列出了此类设备发现问题](https://support.google.com/chromecast/answer/7566322?hl=en)。

认证系统还可能同时绑定 MAC、IP、接入位置或会话。因此，**树莓派认证成功，不代表目标设备一定能联网**。以下步骤用于检验这件事，结果仍需如实记录。

## 二、完整执行流程

```mermaid
flowchart TD
    A["获取本人目标设备的 Wi-Fi MAC"] --> B["确认网络许可和设备归属"]
    B --> C{"树莓派能否稳定操作？"}
    C -- "否" --> D["配置本地终端或独立 SSH/VNC"]
    D --> C
    C -- "是" --> E["只读检查、关闭目标设备"]
    E --> F["运行 quick-start.sh"]
    F --> G["输入 MAC 并临时连接 Portal Wi-Fi"]
    G --> H{"MAC、IP、出口正确？"}
    H -- "否" --> R["停止并恢复树莓派"]
    H -- "是" --> I["本人登录官方 Portal"]
    I --> R
    R --> J["确认树莓派退出目标 MAC"]
    J --> K["重启目标设备并测试联网"]
    K --> L["记录结论、失败原因或后续复测"]
```

## 三、先自行获取目标设备的 MAC

任选一种方式：

1. **个人热点：** 让目标设备临时连接自己的手机热点，在手机的“已连接设备”中读取它的物理地址（MAC）。
2. **私人路由器：** 查看路由器后台的客户端/在线设备列表，找到目标设备及其 MAC。
3. **设备设置或配套应用：** 如果能展示 Wi-Fi MAC，可直接读取。

MAC 示例：`aa:bb:cc:dd:ee:ff`。注意 `192.168.1.20` 是 IP 地址，不能代替 MAC。部分设备会按不同 Wi-Fi 使用随机 MAC；有条件时应核实其在目标网络上实际使用的地址。**不要将个人真实 MAC 原文发布到 GitHub、博客或 Issue。**

## 四、控制树莓派：有屏和无屏都可以

### 方式 A：树莓派有显示器

直接连接显示器、键盘，进入 Raspberry Pi OS 桌面，在树莓派本机终端运行项目脚本即可。鼠标用于浏览器登录和桌面操作。

### 方式 B：树莓派没有显示器——SSH 命令行

**没有屏幕时，单独连接鼠标和键盘无法看到操作结果。** 推荐通过 Windows 使用 SSH 控制树莓派；树莓派本身不需要外接鼠标、键盘或显示器。

如果是首次安装：

1. 在 Windows 使用官方 **Raspberry Pi Imager** 安装 Raspberry Pi OS；**写入镜像会清空目标存储卡，已有数据须先备份**。
2. 在系统自定义设置中设置自己的用户名、密码、主机名、私人 Wi-Fi，并开启 SSH。
3. 树莓派启动后，让 Windows 与树莓派接入同一**私人路由器或个人热点**，查询树莓派的局域网 IP。
4. 在 Windows PowerShell 运行（替换示例用户名和地址）：

   ```powershell
   ssh myuser@192.168.1.42
   ```

5. 在 SSH 终端核验：

   ```bash
   hostname
   whoami
   cat /etc/os-release
   ```

看到树莓派的主机名、用户名和系统信息，就说明远程命令行可用。新版 Raspberry Pi OS 没有固定默认登录密码，应该使用安装时设置的凭据。

**重要：通过树莓派 `wlan0` 建立的 SSH 仅适合初次配置。** 后续脚本需要切换这张 Wi-Fi 网卡的 MAC；如果 SSH 也走 `wlan0`，连接会断开，脚本会拒绝继续。正式实验前，需要改用本地终端或下列独立管理连接。

### 方式 C：独立网线管理——推荐用于正式实验

可选两种拓扑：

- **私人路由器：** 树莓派 `eth0` 接路由器 LAN，Windows 连同一私人路由器，通过树莓派的**有线 IP** SSH。
- **Windows 网线直连：** Windows 有线网口接树莓派 `eth0`；在确认现有配置无冲突后，使用静态管理网段，例如 Windows `192.168.88.1/24`，树莓派 `192.168.88.2/24`，**均不为该管理网线设置默认网关**。

项目提供了管理网线配置脚本。树莓派需先通过**另一条已存在的控制途径**运行：

```bash
bash scripts/ethernet-management.sh check
bash scripts/ethernet-management.sh prepare
```

按提示配置 Windows 有线地址、接好网线后，在树莓派运行：

```bash
bash scripts/ethernet-management.sh up
```

然后 Windows 测试：

```powershell
ssh myuser@192.168.88.2
```

**只有通过有线 SSH 稳定登录成功后，才开始修改树莓派 Wi-Fi。** 如果树莓派 `eth0` 正被其他业务使用，辅助脚本会拒绝抢占。详细 Windows 点击路径、回滚及网络冲突处理参见 [`docs/connection-methods.md`](docs/connection-methods.md)。

Windows Internet Connection Sharing（ICS）可在允许共享的私人网络上临时用于首次配置，但会引入 NAT 和默认网关，容易造成 Portal 认证流量走错出口；**正式实验优先使用无默认网关的独立管理链路**。

### 方式 D：无显示器也想操作图形桌面——VNC

若树莓派安装了带桌面的 Raspberry Pi OS，可以在已经建立的 SSH 终端里运行：

```bash
sudo raspi-config
```

选择 `Interface Options → VNC → Yes`，在 Windows 上使用兼容的 VNC Viewer 连接树莓派的**有线管理 IP**。

这样可以在 Windows 上看到树莓派桌面，使用鼠标和键盘操作浏览器。**VNC 需要图形桌面系统；Raspberry Pi OS Lite 不支持官方桌面 VNC。** 不同桌面/显示服务版本可能还需要配置无屏虚拟显示或分辨率。Raspberry Pi Connect 也提供远程桌面/终端，但其网络依赖使它不适合作为本实验唯一的管理通道。

本教程官方参考：[树莓派远程访问](https://www.raspberrypi.com/documentation/computers/remote-access.html)、[树莓派无屏初始化](https://www.raspberrypi.com/documentation/computers/getting-started.html)。

## 五、下载项目并运行

从 [GitHub Release v0.3.2](https://github.com/Xplore-LAB/portal-mac-experiment/releases/tag/v0.3.2) 下载 `portal-mac-experiment-v0.3.2.zip`；源码和更新见 [项目仓库](https://github.com/Xplore-LAB/portal-mac-experiment)。

项目文件结构：

```text
portal-mac-experiment/
├── .gitignore
├── .github/workflows/check.yml
├── README.md
├── TUTORIAL.md
├── SECURITY.md
├── GITHUB_UPLOAD_CHECKLIST.md
├── quick-start.sh
├── setup-launcher.sh
├── scripts/
│   ├── portal-mac.sh
│   ├── ethernet-management.sh
│   └── wizard.sh
├── docs/
│   └── connection-methods.md
├── experiments/
│   └── result-template.yaml
└── tests/
    ├── smoke.sh
    └── regression.py
```

**有桌面：** 用 U 盘将压缩包复制到树莓派并解压，在文件管理器中打开项目目录和终端。

**使用 SSH：** 将 ZIP 放到 Windows 当前 PowerShell 目录，再传输到树莓派：

```powershell
scp .\portal-mac-experiment-v0.3.2.zip myuser@192.168.88.2:
ssh myuser@192.168.88.2
```

以下命令在登录后的**树莓派终端**运行：

```bash
unzip portal-mac-experiment-v0.3.2.zip
cd portal-mac-experiment
bash quick-start.sh --check
```

### 一键实验入口

```bash
bash quick-start.sh
```

- **首次运行：** 设置一次目标 Wi-Fi SSID，再输入目标 MAC。
- **以后运行：** 只需输入目标 MAC，按提示完成安全确认。
- **重新设置 SSID：** `bash quick-start.sh --setup`。

请用普通用户运行以上命令，由脚本按需调用 `sudo nmcli`；不要在整段引导外套 `sudo`，以免 SSH 环境信息丢失。默认无线接口是 `wlan0`，其他接口可使用 `WIFI_IF=wlan1 bash quick-start.sh`。

接受的 MAC 格式包括 `aa:bb:cc:dd:ee:ff`、`aa-bb-cc-dd-ee-ff` 或 `aabbccddeeff`。快速入口只持久保存 SSID；临时 NetworkManager 配置在内存中包含 MAC，脚本输出也会显示 MAC 和 IP，均须脱敏。脚本不收集 Portal 账号密码，浏览器可能另行保存 Cookie 或凭据。引导会在关键步骤要求输入 `YES` 确认。

图形桌面可另外运行一次 `bash setup-launcher.sh` 创建桌面入口，以后双击启动。

### 一键脚本完成哪些事情？

1. 检查 `nmcli`、Wi-Fi 接口、IP 转发和 SSH 管理路由。
2. 要求目标设备完全离线，避免两个设备同时使用同一 MAC。
3. 创建独立、不可自动连接的临时 Wi-Fi 配置，切换并核查实际 MAC。
4. 查看 Wi-Fi 地址及默认流量出口，阻止明显从有线管理网络出网的误判。
5. 在带桌面时尝试打开普通 HTTP 页面，由用户确认官方 Portal 页面并**亲自输入凭据**。
6. 用户确认后停止测试连接、删除脚本创建的临时配置，并提示再次核查 MAC 是否恢复。

没有桌面时，Portal 登录需要额外使用网络管理方允许的命令行认证工具，或经明确许可采用本地 SSH SOCKS 浏览器通道（参见连接指南）。无法合法完成网页登录时，请停止实验，不要将“已关联 Wi-Fi”误判为“Portal 已认证”。

## 六、手动执行与清理

需要逐步排障时，在树莓派项目目录运行：

```bash
bash scripts/portal-mac.sh check
bash scripts/portal-mac.sh prepare
bash scripts/portal-mac.sh connect
bash scripts/portal-mac.sh status
```

如果 MAC 未生效、没有获取 IP、路由出口不对，停止认证流程。实验完成或者需要放弃时：

```bash
bash scripts/portal-mac.sh restore
```

`restore` 会尝试停止临时测试连接、删除本项目创建的配置；它不保证驱动立即恢复原 MAC，也不会自动重连原 Wi-Fi。临时测试配置采用 `save no`，NetworkManager 重启后会消失；配置已消失时仍须核查无线状态。**恢复后应确认树莓派不再使用目标设备 MAC；不确定时先关闭树莓派，再启动目标设备。** 切勿在两个设备同时在线时使用相同 MAC。

## 七、怎样判断是否成功？

脚本只检查到 `1.1.1.1` 的 IPv4 出口，不能替代对 Portal 服务器、浏览器代理、VPN、DNS 与 IPv6 路径的核查。正式实验优先使用无默认网关的独立管理链路；不能仅凭浏览器打开了某个网页便宣布认证成功。

| 观察项目 | 判定依据 |
|---|---|
| MAC 修改生效 | 树莓派实际无线 MAC 与目标设备一致 |
| 测试网络关联成功 | 测试 Wi-Fi 已连接并分配地址 |
| Portal 认证成功 | 在确认使用测试 Wi-Fi 出口的情况下可以访问公网 |
| 目标设备继承认证 | 树莓派退出后，目标设备无需网页操作即可联网 |
| 重启后仍有效 | 目标设备重启后依然可以联网 |

将脱敏后的观测结果填写到 `experiments/result-template.yaml`，用 `null` 表示未测、`false` 表示实测失败。如果 Portal 成功而目标设备无法联网，可能存在 IP、会话或接入位置绑定；将其作为实验结果记录，**不反复规避网络管理策略**。

## 八、常见问题

**Q：为什么连接着 Wi-Fi 的 SSH 能用，切换 MAC 却不行？** 远程 SSH 会话本身依赖无线接口，修改 `wlan0` 会中断原有管理连接。先建立独立有线管理通道。

**Q：没有显示器又没有桌面，能在 Windows 图形化登录吗？** 可以为带桌面的树莓派配置 VNC。Lite 系统主要采用 SSH；是否能用 Windows 浏览器经过受许可的 SSH 通道代为操作，还要看网络规则和出口路由。

**Q：一次成功是否代表认证永久有效？** 不能。认证会过期，IP、网络位置或会话变化也可能触发重新登录。目前脚本是**一次性验证**，没有后台守护和自动重登功能。

**Q：现在可以直接上传 GitHub 宣称项目成熟吗？** 可作为实验性项目发布，但应明确标记待实机验证。本版尚未指定许可证，以实验性项目公开，不宣称已授予开源许可。

## 九、隐私、安全与技术交流声明

> 本项目仅用于计算机网络技术学习、个人设备兼容性研究，以及获得网络管理方明确授权的 Portal 认证实验。不同网络的管理规定与服务条款优先；未经许可不得进行 MAC 模拟测试。

- 仅操作本人或明确获授权的设备、MAC 地址及账号。
- 真实 MAC、个人 IP、用户名、Portal Cookie、Token、验证码和密码不得提交仓库或公开日志。
- 不修改设备固件，不刷机，不开启未经许可的转发、NAT、网关或网络共享。
- 提前准备独立管理通道，避免 Wi-Fi 切换导致失联。
- 脚本的回滚措施属于尽力保护，仍需要用户确认无线网卡状态；异常时让目标设备和树莓派保持离线，直至排查完成。
- 任何公开结论需分别报告“MAC 生效”“Portal 登录成功”“目标设备继承成功”，不得混为一谈。

## 十、主要参考资料

1. [Raspberry Pi 官方：Getting started / Headless setup](https://www.raspberrypi.com/documentation/computers/getting-started.html)
2. [Raspberry Pi 官方：Remote access（SSH、VNC、Connect）](https://www.raspberrypi.com/documentation/computers/remote-access.html)
3. [NetworkManager：nmcli](https://networkmanager.dev/docs/api/latest/nmcli.html)
4. [NetworkManager：Wi-Fi cloned-mac-address](https://networkmanager.dev/docs/api/latest/nm-settings-nmcli.html)
5. [Microsoft：Internet Connection Sharing](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ics/shared-connections)
6. [Cornell IT：没有浏览器的设备如何登记联网](https://it.cornell.edu/wifi/register-device-doesnt-have-browser)
7. [Apple：HomePod 的官方网页认证网络设置示例](https://support.apple.com/guide/homepod/set-up-homepod-apd779d9bb45/homepod)
8. [Google：联网与设备发现问题排查](https://support.google.com/chromecast/answer/7566322?hl=en)

**实验状态更新建议：** 首先完成只读检查；随后单独验证有线 SSH/VNC 管理通道；最后才进行获得授权的 MAC 与 Portal 实验。公开结论应区分离线检查、用户反馈与本次实机验证，未测步骤保持“待验证”。
