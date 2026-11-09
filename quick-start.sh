#!/usr/bin/env bash
# Guided one-command entry for an authorized, one-time Portal MAC experiment.
# First run: save only the target Wi-Fi SSID. Later runs: enter only target MAC.
# Portal credentials are never collected or saved. The core requires confirmations.
set -Eeuo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
core_script="${project_dir}/scripts/portal-mac.sh"
wizard_script="${project_dir}/scripts/wizard.sh"
settings_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/portal-mac-test"
ssid_file="${settings_dir}/quick-start-ssid"

info() { printf '[引导] %s\n' "$*"; }
die() { printf '[停止] %s\n' "$*" >&2; exit 1; }

help_text() {
  printf '%s\n' \
    '用法：bash quick-start.sh [--setup|--check|--help]' \
    '  无参数  首次输入 SSID 与目标 MAC；以后只需输入目标 MAC' \
    '  --setup   重新设置目标 Wi-Fi SSID（不会保存账号或密码）' \
    '  --check   只读检查树莓派网络与管理通道'
}

save_ssid() {
  local new_ssid confirm LC_ALL=C
  if [[ -e "$ssid_file" ]]; then
    read -r -p '本机已有 Wi-Fi 预设。要更换吗？输入 YES：' confirm
    [[ "$confirm" == 'YES' ]] || die '已取消更新，原设置保留。'
  fi
  read -r -p '请输入需要网页认证的 Wi-Fi 名称（SSID，仅首次需要）：' new_ssid
  [[ -n "$new_ssid" ]] || die 'SSID 不能为空。'
  [[ ${#new_ssid} -le 32 && "$new_ssid" != *$'\r'* ]] || die 'SSID 必须为 1–32 字节，且不能包含回车。'
  umask 077
  mkdir -p -- "$settings_dir"
  printf '%s\n' "$new_ssid" > "$ssid_file"
  chmod 600 "$ssid_file"
  info '已在树莓派本机保存 SSID，未保存任何 Portal 登录凭据。'
}

normalize_mac() {
  local input="${1,,}"
  input="${input//-/:}"
  if [[ "$input" =~ ^[[:xdigit:]]{12}$ ]]; then
    input="${input:0:2}:${input:2:2}:${input:4:2}:${input:6:2}:${input:8:2}:${input:10:2}"
  fi
  [[ "$input" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || die 'MAC 地址格式不正确。示例：aa:bb:cc:dd:ee:ff'
  [[ "$input" != '00:00:00:00:00:00' ]] || die '全零 MAC 不是有效的设备地址。'
  local first="${input%%:*}"
  (( (16#${first} & 1) == 0 )) || die '这是组播 MAC，不适合此实验。'
  printf '%s' "$input"
}

check_ssh_safety() {
  [[ -n "${SSH_CONNECTION:-}" ]] || return 0
  command -v ip >/dev/null 2>&1 || die '缺少 ip 命令，无法验证 SSH 管理通道。'
  local client_ip route_line route_dev family=-4
  client_ip="${SSH_CONNECTION%% *}"
  [[ "$client_ip" != *:* ]] || family=-6
  route_line="$(ip "$family" route get "$client_ip" 2>/dev/null)" || die '无法确认 SSH 连接走哪张网卡，请改用本机终端操作。'
  route_dev="$(awk '{for(i=1;i<NF;i++) if($i=="dev") {print $(i+1); exit}}' <<< "$route_line")"
  [[ -n "$route_dev" ]] || die '无法识别 SSH 管理接口。'
  if [[ "$route_dev" == "${WIFI_IF:-wlan0}" ]]; then
    die "当前 SSH 经过 ${route_dev}。修改这张 Wi-Fi 网卡会导致断线。请改用树莓派本机终端或独立有线 SSH。"
  fi
  info "已确认 SSH 管理接口：${route_dev}"
}

case "${1:-}" in
  --help|-h) help_text; exit 0 ;;
  --check) exec bash "$core_script" check ;;
  --setup) save_ssid; exit 0 ;;
  '') ;;
  *) help_text; exit 2 ;;
esac

printf '\n%s\n' '无屏设备 Portal 一次性认证实验 · 快速入口'
info '此实验仅适用于本人设备、本人账号且网络管理方允许的情形。'
check_ssh_safety

if [[ ! -r "$ssid_file" ]]; then
  info '检测到首次使用，请设置一次目标 Wi-Fi 名称。'
  save_ssid
fi
IFS= read -r ssid < "$ssid_file" || true
[[ -n "${ssid:-}" ]] || die '已保存的 SSID 为空，请运行 bash quick-start.sh --setup 重新设置。'

read -r -p '请输入目标设备 Wi-Fi MAC（支持冒号、横杠或 12 位连续十六进制）：' raw_mac
target_mac="$(normalize_mac "$raw_mac")"
export PORTAL_SSID="$ssid" PORTAL_TARGET_MAC="$target_mac"

info "目标 Wi-Fi：${ssid}"
info '请先确保目标设备已经离线。接下来需确认安全操作，并由本人登录 Portal 网页。'
exec bash "$wizard_script"
