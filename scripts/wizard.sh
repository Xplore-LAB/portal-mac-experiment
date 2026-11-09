#!/usr/bin/env bash
# Interactive desktop wizard for one-time MAC / captive portal experiment.
# No credentials are collected or stored by this script.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
core_script="${script_dir}/portal-mac.sh"
cleanup_pending=0

say() { printf '\n%s\n' "$*"; }
warn() { printf '[注意] %s\n' "$*" >&2; }

cleanup_when_exiting() {
  local original_status=$?
  trap - EXIT
  if (( cleanup_pending )); then
    # Only act on a profile carrying the exact marker set by our own core script.
    if command -v nmcli >/dev/null 2>&1; then
      local marker
      marker="$(nmcli --escape no -g connection.stable-id connection show portal-mac-test 2>/dev/null || true)"
      if [[ "$marker" == 'portal-mac-test-owned-v1' ]]; then
        warn '引导程序提前结束，尝试自动停止并删除临时测试连接。'
        if ! bash "$core_script" restore; then
          warn '自动恢复未完成：请保持目标设备离线，将树莓派关机后再人工排查。'
        fi
      fi
    fi
  fi
  if (( original_status != 0 )) && [[ -t 0 ]]; then
    warn '程序提前结束。请阅读上述错误信息，并确认树莓派当前无线 MAC 与连接状态。'
    read -r -p '按 Enter 关闭此窗口：' _ || true
  fi
  return "$original_status"
}
trap cleanup_when_exiting EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

say '========================================'
say '  无屏设备 Portal 认证实验 · 引导模式'
say '========================================'
say '本程序依次执行检查、临时 MAC 连接和恢复。'
say '登录网页仍需你本人操作，程序不会索取或保存网络账号密码。'
say '准备好显示器、键盘及鼠标；通过无线网卡本身建立的 SSH 不安全。'

if [[ -n "${PORTAL_SSID:-}" && -n "${PORTAL_TARGET_MAC:-}" ]]; then
  export PORTAL_SSID PORTAL_TARGET_MAC
  say '已填入目标 Wi-Fi 和 MAC；仍需要安全确认及本人网页登录。'
fi

read -r -p '请先记录目标设备的 Wi-Fi MAC，并将目标设备断电。准备好后按 Enter：' _

say '[第 1/5 步] 只读检查树莓派'
bash "$core_script" check

say '[第 2/5 步] 创建临时网络配置'
bash "$core_script" prepare
cleanup_pending=1

say '[第 3/5 步] 使用目标 MAC 连接 Portal 网络'
bash "$core_script" connect

say '[第 4/5 步] 打开网页，由你亲自完成认证'
say '将尝试打开一个普通 HTTP 页面，供网络将其重定向到官方认证页。'
warn '只有确认跳转到可信的网络官方登录页面后，才能输入账号密码。'
if command -v xdg-open >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  xdg-open 'http://example.com/' >/dev/null 2>&1 &
  say '已尝试打开浏览器。若没有自动出现认证页，请手动访问网络提供的正式认证地址。'
else
  warn '当前没有可用图形桌面。请通过本机浏览器或经审查的合法命令行客户端完成认证。'
fi

read -r -p '完成认证、确认联网结果或决定放弃后，切回本终端按 Enter 执行恢复：' _

say '[第 5/5 步] 断开测试连接并清理临时配置'
bash "$core_script" restore
cleanup_pending=0

say '引导结束。'
say '请确认树莓派不再使用目标 MAC；建议将树莓派关机，再启动目标设备连接同一 Wi-Fi。'
say '记录目标设备是否能直接联网，以及重启后是否仍然有效。'
read -r -p '按 Enter 关闭窗口：' _
