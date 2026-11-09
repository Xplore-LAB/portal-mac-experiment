#!/usr/bin/env bash
# Optional isolated Windows <-> Raspberry Pi management link.
# Configure eth0 with a private static address and NO default gateway / NAT.
set -Eeuo pipefail

ETH_IF="${ETH_IF:-eth0}"
MGMT_PROFILE='portal-mgmt-static'
MGMT_MARKER='portal-mgmt-static-owned-v1'
PI_CIDR='192.168.88.2/24'

info() { printf '[INFO] %s\n' "$*"; }
die() { printf '[STOP] %s\n' "$*" >&2; exit 1; }

need() {
  for bin in nmcli ip sudo; do
    command -v "$bin" >/dev/null 2>&1 || die "缺少命令：${bin}"
  done
  [[ -e "/sys/class/net/${ETH_IF}/address" ]] || die "找不到有线接口 ${ETH_IF}。"
  [[ "$(nmcli --escape no -g GENERAL.TYPE device show "$ETH_IF" 2>/dev/null)" == 'ethernet' ]] || die "${ETH_IF} 不是 Ethernet 接口。"
}

is_managed_profile() {
  [[ "$(nmcli --escape no -g connection.stable-id connection show "$MGMT_PROFILE" 2>/dev/null || true)" == "$MGMT_MARKER" ]]
}

ssh_route_device() {
  [[ -n "${SSH_CONNECTION:-}" ]] || return 0
  local remote_ip route_line family=-4
  read -r remote_ip _ <<< "$SSH_CONNECTION"
  [[ "$remote_ip" != *:* ]] || family=-6
  route_line="$(ip "$family" route get "$remote_ip" 2>/dev/null)" || die '无法识别当前 SSH 连接路由。'
  awk '{for(i=1;i<NF;i++) if($i=="dev") {print $(i+1); exit}}' <<< "$route_line"
}

run_check() {
  need
  ip -br address show dev "$ETH_IF"
  nmcli -f GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS device show "$ETH_IF"
  ip -4 route get 1.1.1.1 || true
  info "当前 SSH 管理接口：$(ssh_route_device)"
}

run_prepare() {
  need
  nmcli connection show "$MGMT_PROFILE" >/dev/null 2>&1 && die "已有同名连接 ${MGMT_PROFILE}，拒绝覆盖。"
  local active confirmation
  active="$(nmcli --escape no -g GENERAL.CONNECTION device show "$ETH_IF")"
  if [[ -n "$active" && "$active" != '--' ]]; then
    die "${ETH_IF} 正由连接 ${active} 使用，拒绝覆盖或抢占。请保持现有有线连接。"
  fi
  info '本方案的管理地址：Windows Ethernet = 192.168.88.1/24；树莓派 eth0 = 192.168.88.2/24。'
  info '不会配置默认网关，也不会启用 NAT。请确保该网段与现有局域网不冲突。'
  read -r -p '已确认网络地址不冲突，并有另一条可用控制通道？输入 YES：' confirmation
  [[ "$confirmation" == YES ]] || die '用户取消。'
  sudo nmcli connection add type ethernet ifname "$ETH_IF" \
    con-name "$MGMT_PROFILE" \
    connection.stable-id "$MGMT_MARKER" \
    connection.autoconnect no \
    ipv4.method manual ipv4.addresses "$PI_CIDR" \
    ipv4.never-default yes ipv6.method disabled
  is_managed_profile || die '测试配置标记不符，未继续。'
  info '已新建独立的有线管理配置。使用 up 激活，不会修改原有连接。'
}

run_up() {
  need
  is_managed_profile || die '找不到本脚本创建的有线管理配置。请先 prepare。'
  local confirmation active current_ssh_dev
  read -r -p 'Windows Ethernet 已配置 192.168.88.1/24 且网线接好？输入 YES：' confirmation
  [[ "$confirmation" == YES ]] || die '用户取消。'
  active="$(nmcli --escape no -g GENERAL.CONNECTION device show "$ETH_IF")"
  if [[ -n "$active" && "$active" != '--' && "$active" != "$MGMT_PROFILE" ]]; then
    die "${ETH_IF} 现在正由连接 ${active} 使用，拒绝抢占。"
  fi
  if [[ "$active" == "$MGMT_PROFILE" ]]; then
    info '有线管理配置已经启用，无需再次切换。'
    return 0
  fi
  current_ssh_dev="$(ssh_route_device)"
  [[ "$current_ssh_dev" != "$ETH_IF" ]] || die '当前 SSH 正经过待切换的有线接口，请使用其他管理通道。'
  sudo nmcli connection up "$MGMT_PROFILE" ifname "$ETH_IF"
  ip -4 address show dev "$ETH_IF"
  info '现在从 Windows 测试 ssh 用户名@192.168.88.2。必须验证可用后再切换树莓派 Wi-Fi。'
}

run_restore() {
  need
  is_managed_profile || die '找不到本脚本创建的有线管理配置，拒绝删除其他连接。'
  local current_ssh_dev active
  current_ssh_dev="$(ssh_route_device)"
  [[ "$current_ssh_dev" != "$ETH_IF" ]] || die '当前 SSH 正使用待断开的有线接口，拒绝恢复。请改走本地终端或其他独立连接。'
  active="$(nmcli --escape no -g GENERAL.CONNECTION device show "$ETH_IF")"
  if [[ "$active" == "$MGMT_PROFILE" ]]; then
    sudo nmcli device down "$ETH_IF"
  fi
  sudo nmcli connection delete "$MGMT_PROFILE"
  info '本脚本创建的静态有线管理配置已删除。Windows Ethernet 的静态 IP 如有设置，请自行恢复原状。'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
case "${1:-}" in
  check) run_check ;;
  prepare) run_prepare ;;
  up) run_up ;;
  restore) run_restore ;;
  *) printf '%s\n' '用法：bash scripts/ethernet-management.sh {check|prepare|up|restore}' ; exit 2 ;;
esac
fi
