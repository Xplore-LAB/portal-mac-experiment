#!/usr/bin/env bash
# Temporary MAC cloning for a user-owned headless device on a permitted captive portal.
# No login credentials, routing, NAT, firmware edits or background services.
set -Eeuo pipefail

WIFI_IF="${WIFI_IF:-wlan0}"
PROFILE_ID="portal-mac-test"
PROFILE_MARKER="portal-mac-test-owned-v1"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[STOP] %s\n' "$*" >&2; exit 1; }

help_text() {
  printf '%s\n' \
    '用法：bash scripts/portal-mac.sh {check|prepare|connect|status|restore}' \
    '可选：WIFI_IF=wlan1 bash scripts/portal-mac.sh check' \
    '注意：需有独立管理通道；网络管理方允许后方可实验。'
}

require_tools() {
  for executable in nmcli ip awk sudo grep tr sysctl; do
    command -v "$executable" >/dev/null 2>&1 || die "缺少 ${executable}。请先识别系统环境；本脚本不负责安装或修改网络管理软件。"
  done
  [[ -e "/sys/class/net/${WIFI_IF}/address" ]] || die "无线接口 ${WIFI_IF} 不存在。请先运行 ip -br link 确认名称。"
  nmcli --escape no -g GENERAL.TYPE device show "$WIFI_IF" 2>/dev/null | grep -qx 'wifi' || die "${WIFI_IF} 不是 NetworkManager 管理的 Wi-Fi 设备。"
}

read_wifi_mac() {
  tr '[:upper:]' '[:lower:]' < "/sys/class/net/${WIFI_IF}/address"
}

check_management_path() {
  # In an SSH shell, the source IP should be reached via an interface OTHER than WIFI_IF.
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    local client_ip route_line route_dev family=-4
    read -r client_ip _ <<< "$SSH_CONNECTION"
    [[ "$client_ip" != *:* ]] || family=-6
    route_line="$(ip "$family" route get "$client_ip" 2>/dev/null)" || die "无法确认当前 SSH 返回路径；请改用本地终端操作。"
    route_dev="$(awk '{for (i=1; i<NF; i++) if ($i=="dev") {print $(i+1); exit}}' <<< "$route_line")"
    [[ -n "$route_dev" ]] || die "未能识别 SSH 所用接口；请改用本地终端操作。"
    info "SSH 管理通道：${route_dev}"
    [[ "$route_dev" != "$WIFI_IF" ]] || die "SSH 正通过 ${WIFI_IF} 连接。修改该接口会断开 SSH，禁止继续。"
  else
    warn '未检测到 SSH_CONNECTION。请确认你正在树莓派本地显示器/键盘上操作，或有其他可靠管理通道。'
  fi
}

check_no_forwarding() {
  local enabled
  enabled="$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" || die '无法读取 IP 转发状态。'
  [[ "$enabled" == 0 ]] || die 'IPv4 转发已启用。请先确认设备没有承担网关或网络共享任务；本实验停止。'
}

profile_exists() {
  nmcli connection show "$PROFILE_ID" >/dev/null 2>&1
}

require_own_profile() {
  profile_exists || die "未找到测试连接 ${PROFILE_ID}。请先运行 prepare。"
  local marker
  marker="$(nmcli --escape no -g connection.stable-id connection show "$PROFILE_ID" 2>/dev/null)" || die '无法读取测试连接标记。'
  [[ "$marker" == "$PROFILE_MARKER" ]] || die "存在同名连接，但并非本脚本创建。为保护原配置，拒绝修改或删除。"
}

is_valid_unicast_mac() {
  local candidate="$1" first
  [[ "$candidate" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || return 1
  [[ "$candidate" != '00:00:00:00:00:00' ]] || return 1
  first="${candidate%%:*}"
  (( (16#${first} & 1) == 0 ))
}

confirm() {
  local response
  read -r -p "$1 请完整输入 YES 确认：" response
  [[ "$response" == 'YES' ]] || die '用户未确认，未执行网络修改。'
}

run_check() {
  require_tools
  printf '\n[设备型号]\n'
  if [[ -r /proc/device-tree/model ]]; then
    tr -d '\0' < /proc/device-tree/model
    printf '\n'
  else
    info '设备型号信息不可用。'
  fi
  printf '\n[系统]\n'
  if [[ -r /etc/os-release ]]; then
    grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release || true
  fi
  printf '\n[NetworkManager]\n'
  nmcli --version
  printf '\n[接口当前状态]\n'
  ip -br link show "$WIFI_IF"
  nmcli -f DEVICE,TYPE,STATE,CONNECTION device status
  printf '\n[管理通道]\n'
  check_management_path
  printf '\n[IP 转发]\n'
  check_no_forwarding
  info '只读检查完成。'
}

run_prepare() {
  require_tools
  check_management_path
  check_no_forwarding
  profile_exists && die "${PROFILE_ID} 已存在，拒绝覆盖。若属于本脚本的旧实验，请先运行 restore。"
  local ssid="${PORTAL_SSID:-}" target_mac="${PORTAL_TARGET_MAC:-}" LC_ALL=C
  if [[ -z "$ssid" ]]; then
    read -r -p '请输入需要网页认证的开放式 Wi-Fi SSID：' ssid
  else
    info "已读取本地预设 SSID：${ssid}"
  fi
  [[ -n "$ssid" ]] || die 'SSID 不能为空。'
  [[ ${#ssid} -le 32 && "$ssid" != *$'\r'* && "$ssid" != *$'\n'* ]] || die 'SSID 必须为 1–32 字节，且不能包含换行。'
  if [[ -z "$target_mac" ]]; then
    read -r -p '请输入目标设备实际 Wi-Fi MAC（xx:xx:xx:xx:xx:xx）：' target_mac
  else
    info '已读取本地预设的目标 MAC。'
  fi
  is_valid_unicast_mac "$target_mac" || die '无效的单播 MAC 地址。'
  confirm '已获得网络管理方许可，且已准备好独立管理通道？'
  sudo nmcli connection add save no \
    type wifi ifname "$WIFI_IF" con-name "$PROFILE_ID" ssid "$ssid" \
    connection.autoconnect no \
    connection.stable-id "$PROFILE_MARKER" \
    ipv4.method auto ipv4.may-fail no \
    802-11-wireless.cloned-mac-address "$target_mac"
  require_own_profile
  info '已创建仅驻留内存的测试连接，但没有激活 Wi-Fi；NetworkManager 重启后该配置消失。'
  info "本次模拟 MAC：$(nmcli --escape no -g 802-11-wireless.cloned-mac-address connection show "$PROFILE_ID")"
}

run_connect() {
  require_tools
  check_management_path
  check_no_forwarding
  require_own_profile
  local expected effective route_line route_dev
  expected="$(nmcli --escape no -g 802-11-wireless.cloned-mac-address connection show "$PROFILE_ID")"
  is_valid_unicast_mac "$expected" || die '测试配置中的目标 MAC 无效。'
  confirm "目标设备已断电或完全离线，且当前只有树莓派会使用 ${expected}？"
  info '正在切换无线连接；如驱动不支持指定 MAC，将停止测试。'
  if ! sudo nmcli --wait 45 connection up "$PROFILE_ID" ifname "$WIFI_IF"; then
    warn '连接失败，尝试停止该无线接口。'
    sudo nmcli device down "$WIFI_IF" || true
    die '请运行 restore 清除测试配置。保持目标设备离线，直到树莓派停止使用相同 MAC。'
  fi
  effective="$(read_wifi_mac)"
  if [[ "$effective" != "${expected,,}" ]]; then
    warn "实际 MAC 为 ${effective}，与目标 ${expected} 不一致。"
    sudo nmcli device down "$WIFI_IF" || true
    die '已经停止无线连接。请运行 restore，不要继续登录 Portal。'
  fi
  info "MAC 已生效：${effective}"
  printf '\n[Wi-Fi IPv4]\n'
  ip -4 address show dev "$WIFI_IF"
  if ! ip -4 -o address show dev "$WIFI_IF" scope global | grep -q ' inet '; then
    sudo nmcli device down "$WIFI_IF" || true
    die '测试 Wi-Fi 尚无 IPv4 地址，已断开。请运行 restore，暂不登录 Portal。'
  fi
  printf '\n[公网地址默认出口诊断]\n'
  route_line="$(ip -4 route get 1.1.1.1 2>/dev/null)" || {
    sudo nmcli device down "$WIFI_IF" || true
    die '无法确定公网流量出口，已断开测试 Wi-Fi。请保留目标设备离线并运行 restore。'
  }
  printf '%s\n' "$route_line"
  route_dev="$(awk '{for(i=1;i<NF;i++) if($i=="dev") {print $(i+1); exit}}' <<< "$route_line")"
  if [[ "$route_dev" != "$WIFI_IF" ]]; then
    warn "当前默认出口是 ${route_dev:-未知接口}，不是测试 Wi-Fi ${WIFI_IF}。"
    sudo nmcli device down "$WIFI_IF" || true
    die '为避免把管理网络误判为 Portal 认证结果，已停止测试连接。请先修正路由，再运行 restore 清理配置。'
  fi
  info "已确认公网目标路由使用 ${WIFI_IF}。Portal 服务器自身的路由仍需单独核对。"
  warn '请在该 Wi-Fi 链路上使用本人的账号完成 Portal 登录，并记录结果。'
  warn '如果浏览器实际经有线连接上网，不能据此判断 Wi-Fi 认证成功。'
}

run_status() {
  require_tools
  printf '[当前 Wi-Fi MAC]\n'
  ip -br link show "$WIFI_IF"
  printf '\n[当前连接与 IP]\n'
  nmcli -f GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS device show "$WIFI_IF"
  if profile_exists; then
    require_own_profile
    printf '\n[测试配置的模拟 MAC]\n'
    nmcli --escape no -g 802-11-wireless.cloned-mac-address connection show "$PROFILE_ID"
  fi
}

run_restore() {
  require_tools
  if ! profile_exists; then
    info '未找到临时测试配置，无配置可清理。仍需自行确认无线 MAC 与联网状态。'
    return 0
  fi
  check_management_path
  require_own_profile
  local active expected actual
  expected="$(nmcli --escape no -g 802-11-wireless.cloned-mac-address connection show "$PROFILE_ID")"
  active="$(nmcli --escape no -g GENERAL.CONNECTION device show "$WIFI_IF")"
  if [[ "$active" == "$PROFILE_ID" ]]; then
    info '正在停止临时无线连接。'
    sudo nmcli device down "$WIFI_IF"
  else
    info "当前活动连接为 ${active}；不主动断开其他连接。"
  fi
  sudo nmcli connection delete "$PROFILE_ID"
  actual="$(read_wifi_mac)"
  info '测试配置已删除；原有网络配置未被删除。'
  info "当前显示 MAC：${actual}"
  if [[ "$actual" == "${expected,,}" ]]; then
    warn '无线接口当前仍显示模拟 MAC。请将树莓派关机，确保其不再连接网络，之后才启动目标设备。'
  else
    warn '请核实树莓派已经退出该网络。为排除重复 MAC，建议关机后再启动目标设备。'
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
case "${1:-}" in
  check) run_check ;;
  prepare) run_prepare ;;
  connect) run_connect ;;
  status) run_status ;;
  restore) run_restore ;;
  *) help_text; exit 2 ;;
esac
fi
