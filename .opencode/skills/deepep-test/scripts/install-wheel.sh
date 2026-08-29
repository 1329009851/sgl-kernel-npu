#!/usr/bin/env bash
# Phase 4：安装 wheel。pip uninstall deep_ep -> pip install ./output/<wheel> -> 校验 import。
# 用法：bash install-wheel.sh [--wheel <remote-rel-path>]
set -o pipefail
source "$(dirname "$0")/lib.sh"

a5_require_cmd ssh
a5_load_config
PROJ="$(a5_remote_project_path)"

WHEEL_REL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --wheel) WHEEL_REL="$2"; shift 2;;
    -h|--help) sed -n '2,3p' "$0"; exit 0;;
    *) a5_die "未知参数：$1";;
  esac
done

if [ -z "${WHEEL_REL}" ]; then
  a5_info "未指定 wheel，自动定位 output/ 下 deepep 产物"
  WHEEL_REL=$(a5_run_remote "cd '${PROJ}' && ls -1 output/*deep*ep*.whl output/*deepep*.whl 2>/dev/null | head -1") || true
  WHEEL_REL="${WHEEL_REL#$(a5_remote_project_path)/}"
fi
[ -n "${WHEEL_REL}" ] || a5_die "未找到 wheel，请先 build-remote.sh 或用 --wheel 指定"

a5_info "卸载旧 deep_ep（若未装则忽略）"
a5_run_remote "python3 -m pip uninstall -y deep_ep >/dev/null 2>&1; true"

a5_info "安装 wheel：./${WHEEL_REL}"
a5_run_remote "set -o pipefail; cd '${PROJ}' && python3 -m pip install './${WHEEL_REL}' 2>&1" \
  || a5_die "pip install 失败（确认 wheel 为 aarch64 + 对应 Python 版本）"

a5_info "校验 import deep_ep"
a5_run_remote "python3 -c 'import deep_ep; print(\"IMPORT_OK\", deep_ep.__file__)'" \
  || a5_die "import deep_ep 失败"
a5_ok "wheel 安装并导入成功"
