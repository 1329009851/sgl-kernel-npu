#!/usr/bin/env bash
# Phase 3：远程编译。ssh 进 sgl-kernel-npu 跑 build.sh -a deepep Ascend950，
#          检查退出码并定位 output/ 下新编出的 deepep wheel。
# 用法：bash build-remote.sh
# 输出：成功末行打印远程 wheel 相对路径（相对项目目录）。
set -o pipefail
source "$(dirname "$0")/lib.sh"

a5_require_cmd ssh
a5_load_config
PROJ="$(a5_remote_project_path)"

a5_info "远程编译（$(a5_exec_target)）：cd ${PROJ} && ${A5_BUILD_CMD}"
OUT=$(a5_run_remote "set -o pipefail; $(a5_proxy_exports)cd '${PROJ}' 2>/dev/null || { echo '项目目录不存在，先跑 deploy.sh' >&2; exit 2; }; ${A5_BUILD_CMD} 2>&1; echo EXIT=\$?")
EC=$?
if ! echo "${OUT}" | grep -q 'EXIT=0'; then
  a5_die "编译失败，远程日志末 50 行：
$(echo "${OUT}" | grep -v 'EXIT=' | tail -50)"
fi
a5_ok "编译成功"

a5_info "定位 output/ 下 deepep wheel"
WHEEL_REL=$(a5_run_remote "cd '${PROJ}' && ls -1 output/*deep*ep*.whl output/*deepep*.whl 2>/dev/null | head -1") || true
if [ -z "${WHEEL_REL}" ]; then
  a5_warn "未在 output/ 找到 .whl，尝试匹配任意 deepep 产物"
  WHEEL_REL=$(a5_run_remote "cd '${PROJ}' && find output -maxdepth 2 -type f \( -iname '*deep*ep*' -o -iname '*deepep*' \) 2>/dev/null | head -1") || true
fi
[ -n "${WHEEL_REL}" ] || a5_die "未找到编译出的 deepep wheel，请检查 output/ 目录"
WHEEL_REL="${WHEEL_REL#$(a5_remote_project_path)/}"
a5_ok "wheel：${WHEEL_REL}"
echo "${WHEEL_REL}"
