#!/usr/bin/env bash
# Safe offline checks. No network interfaces or user accounts are modified.
set -Eeuo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for relative in \
  quick-start.sh \
  setup-launcher.sh \
  scripts/wizard.sh \
  scripts/portal-mac.sh \
  scripts/ethernet-management.sh; do
  bash -n "${project_dir}/${relative}"
  printf '[OK] 语法：%s\n' "$relative"
done

help_output="$(bash "${project_dir}/quick-start.sh" --help)"
[[ "$help_output" == *'--setup'* ]] || { printf '[失败] 快速入口帮助缺少 --setup\n' >&2; exit 1; }
[[ "$help_output" == *'--check'* ]] || { printf '[失败] 快速入口帮助缺少 --check\n' >&2; exit 1; }

for required in README.md TUTORIAL.md SECURITY.md GITHUB_UPLOAD_CHECKLIST.md experiments/result-template.yaml docs/connection-methods.md; do
  [[ -f "${project_dir}/${required}" ]] || { printf '[失败] 缺少文件：%s\n' "$required" >&2; exit 1; }
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "${project_dir}/quick-start.sh" "${project_dir}/setup-launcher.sh" \
    "${project_dir}"/scripts/*.sh "${project_dir}/tests/smoke.sh"
  printf '[OK] ShellCheck\n'
fi

python3 "${project_dir}/tests/regression.py"

printf '[OK] 离线基本检查通过。实际 MAC、Portal 登录及继承效果仍需实机验证。\n'
