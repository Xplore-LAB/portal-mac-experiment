#!/usr/bin/env bash
# Install a user-level desktop launcher, without sudo or system-wide modifications.
set -Eeuo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
wizard_script="${project_dir}/quick-start.sh"

[[ -f "$wizard_script" ]] || { printf '[错误] 找不到引导脚本。\n' >&2; exit 1; }
[[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || {
  printf '[提示] 请在树莓派的图形桌面终端运行本安装命令。\n' >&2
  exit 1
}

desktop_dir=''
if command -v xdg-user-dir >/dev/null 2>&1; then
  desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
fi
if [[ -z "$desktop_dir" || "$desktop_dir" == "$HOME" ]]; then
  desktop_dir="${HOME}/Desktop"
fi

[[ -d "$desktop_dir" ]] || {
  printf '[错误] 没找到桌面文件夹：%s\n' "$desktop_dir" >&2
  exit 1
}

# Desktop entry uses quoting for whitespace; reject other special path characters.
if [[ "$wizard_script" == *'"'* || "$wizard_script" == *'%'* || "$wizard_script" == *$'\n'* ||
      "$wizard_script" == *\\* || "$wizard_script" == *'$'* || "$wizard_script" == *'`'* ||
      "$wizard_script" == *$'\r'* || "$wizard_script" == *$'\t'* ]]; then
  printf '[错误] 项目所在路径包含不适合桌面入口的特殊字符。请移动项目到简单路径。\n' >&2
  exit 1
fi

launcher_path="${desktop_dir}/Portal-MAC-Test.desktop"
[[ ! -e "$launcher_path" ]] || {
  printf '[停止] 桌面入口已存在：%s。为保护已有文件，不自动覆盖。\n' "$launcher_path" >&2
  exit 1
}

{
  printf '[Desktop Entry]\n'
  printf 'Type=Application\n'
  printf 'Name=Portal MAC 临时认证实验\n'
  printf 'Comment=交互式检查、临时连接和恢复网络配置\n'
  printf 'Exec=/bin/bash "%s"\n' "$wizard_script"
  printf 'Terminal=true\n'
  printf 'Icon=network-wireless\n'
  printf 'Categories=Network;Utility;\n'
} > "$launcher_path"
chmod u+x "$launcher_path"

printf '[完成] 已创建桌面入口：%s\n' "$launcher_path"
printf '[使用] 返回桌面，双击“Portal MAC 临时认证实验”。\n'
printf '[提示] 首次运行输入 Wi-Fi 名称与目标 MAC；以后仅需输入目标 MAC，并完成必要的安全确认和网页登录。\n'
printf '[注意] 某些桌面环境首次会询问是否信任或允许启动，请确认文件来自本项目后再选择启动。\n'
