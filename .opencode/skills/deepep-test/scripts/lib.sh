#!/usr/bin/env bash
# deepep-test 共享库：定位 skill 根、加载/初始化 config、ssh/scp 封装
# 被 scripts/ 下其它脚本 source，不直接执行。

set -o pipefail

SKILL_NAME="deepep-test"

_lib_resolve_root() {
  local src="${BASH_SOURCE[0]}"
  local dir
  dir="$(cd "$(dirname "${src}")" && pwd)"
  echo "$(cd "${dir}/.." && pwd)"
}
A5_SKILL_ROOT="$(_lib_resolve_root)"
A5_SCRIPTS_DIR="${A5_SKILL_ROOT}/scripts"
A5_TEMPLATES_DIR="${A5_SKILL_ROOT}/templates"
A5_CONFIG="${A5_SKILL_ROOT}/config.sh"
A5_TEMPLATE_CONFIG="${A5_TEMPLATES_DIR}/config.sh"

a5_die() { echo "[a5][ERROR] $*" >&2; exit 1; }
a5_info() { echo "[a5][INFO] $*"; }
a5_warn() { echo "[a5][WARN] $*" >&2; }
a5_ok()   { echo "[a5][OK] $*"; }

a5_load_config() {
  if [ ! -f "${A5_CONFIG}" ]; then
    a5_info "首次运行：从模板初始化 ${A5_CONFIG}"
    cp "${A5_TEMPLATE_CONFIG}" "${A5_CONFIG}" 2>/dev/null || \
      a5_die "模板缺失：${A5_TEMPLATE_CONFIG}"
    a5_warn "请编辑 ${A5_CONFIG} 填写 A5_HOST/A5_USER/A5_EMPLOYEE_ID 后重跑。"
    a5_warn "随后执行 setup-ssh.sh 配置免密（首次会询问一次密码）。"
    exit 2
  fi
  # shellcheck disable=SC1090
  source "${A5_CONFIG}"
  : "${A5_HOST:?config.sh 缺 A5_HOST}"
  : "${A5_USER:=root}"
  : "${A5_PORT:=22}"
  : "${A5_EMPLOYEE_ID:=${A5_USER}}"
  : "${A5_REMOTE_HOME:=/home/${A5_EMPLOYEE_ID}}"
  : "${A5_PROJECT_DIR:=sgl-kernel-npu}"
  : "${A5_ZIP_NAME:=sgl-kernel-npu}"
  : "${A5_ARCH:=Ascend950}"
  : "${A5_BUILD_TARGET:=deepep}"
  : "${A5_BUILD_CMD:=bash build.sh -a ${A5_BUILD_TARGET} ${A5_ARCH}}"
  : "${HCCL_BUFFSIZE:=4096}"
  : "${HCCL_NPU_SOCKET_PORT_RANGE:=\"16000,17000\"}"
  : "${HCCL_OP_EXPANSION_MODE:=AIV}"
  : "${A5_TEST_SCRIPT:=tests/python/deepep/test_intranode.py}"
  : "${A5_DEFAULT_NUM_PROCESS:=8}"
  : "${A5_QUANT_TYPE:=pertoken_fp8_e4m3}"
  : "${A5_VISIBLE_DEVICES:=}"
  : "${A5_SSH_KEY_SETUP:=false}"
  : "${A5_DOCKER:=}"
  : "${A5_USE_PROXY:=false}"
  : "${A5_HTTP_PROXY:=}"
  : "${A5_HTTPS_PROXY:=${A5_HTTP_PROXY}}"
  : "${A5_NO_PROXY:=}"
  : "${A5_GIT_SSL_NO_VERIFY:=true}"
  export A5_HOST A5_PORT A5_USER A5_EMPLOYEE_ID A5_REMOTE_HOME A5_PROJECT_DIR \
         A5_ZIP_NAME A5_ARCH A5_BUILD_TARGET A5_BUILD_CMD A5_TEST_SCRIPT \
         A5_DEFAULT_NUM_PROCESS A5_QUANT_TYPE A5_VISIBLE_DEVICES A5_SSH_KEY_SETUP \
         A5_DOCKER \
         A5_USE_PROXY A5_HTTP_PROXY A5_HTTPS_PROXY A5_NO_PROXY A5_GIT_SSL_NO_VERIFY \
         HCCL_BUFFSIZE HCCL_NPU_SOCKET_PORT_RANGE HCCL_OP_EXPANSION_MODE
}

a5_ssh_target() { echo "${A5_USER}@${A5_HOST}"; }
a5_ssh_port_opt() { echo "-p ${A5_PORT}"; }

a5_ssh() {
  ssh -p "${A5_PORT}" -o StrictHostKeyChecking=accept-new -o BatchMode=yes \
    "${A5_USER}@${A5_HOST}" "$@"
}
a5_scp_up() {
  # $1=local path  $2=remote path
  scp -P "${A5_PORT}" -o StrictHostKeyChecking=accept-new -o BatchMode=yes \
    "$1" "${A5_USER}@${A5_HOST}:$2"
}
a5_remote_project_path() { echo "${A5_REMOTE_HOME}/${A5_PROJECT_DIR}"; }

a5_proxy_exports() {
  [ "${A5_USE_PROXY:-false}" = "true" ] || return 0
  printf 'export http_proxy=%s; export https_proxy=%s; export no_proxy=%s; export GIT_SSL_NO_VERIFY=%s; ' \
    "${A5_HTTP_PROXY}" "${A5_HTTPS_PROXY}" "${A5_NO_PROXY}" "${A5_GIT_SSL_NO_VERIFY}"
}

a5_exec_target() {
  if [ -n "${A5_DOCKER:-}" ]; then echo "docker 容器 ${A5_DOCKER}"; else echo "宿主机"; fi
}

a5_qsh() {
  local s="$1"; s="${s//\'/\'\\\'\'}"; printf "'%s'" "${s}"
}

a5_run_remote() {
  local cmd="$1"
  if [ -n "${A5_DOCKER:-}" ]; then
    a5_ssh "docker exec ${A5_DOCKER} bash -lc $(a5_qsh "${cmd}")"
  else
    a5_ssh "${cmd}"
  fi
}

a5_check_ssh_batch() {
  ssh -p "${A5_PORT}" -o BatchMode=yes -o ConnectTimeout=8 \
    "${A5_USER}@${A5_HOST}" 'echo ok' 2>/dev/null
}

a5_print_manual_cmd() {
  local np="$1" qt="$2" vd="${3:-}"
  local proj; proj="$(a5_remote_project_path)"
  echo
  a5_info "测试完成。手动复现命令（在 A5 宿主机执行）："
  {
    if [ -n "${A5_DOCKER:-}" ]; then
      echo "docker exec -it ${A5_DOCKER} bash -lc '"
    else
      echo "bash -lc '"
    fi
    echo "cd ${proj} && \\"
    echo "export HCCL_BUFFSIZE=${HCCL_BUFFSIZE} && \\"
    echo "export HCCL_NPU_SOCKET_PORT_RANGE=\"${HCCL_NPU_SOCKET_PORT_RANGE}\" && \\"
    echo "export HCCL_OP_EXPANSION_MODE=${HCCL_OP_EXPANSION_MODE} && \\"
    if [ -n "${vd}" ]; then
      echo "export ASCEND_RT_VISIBLE_DEVICES=${vd} && \\"
    fi
    echo "python3 ${A5_TEST_SCRIPT} --num-process ${np} --quant-type ${qt}'"
  }
}

a5_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || a5_die "缺少命令：$1"
}
