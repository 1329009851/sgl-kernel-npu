#!/usr/bin/env bash
# Phase 5：HCCL 环境变量。本脚本可被 source 到当前 shell（仅本地参考），
#           真正生效靠 run-test.sh 把这些 export 内联到远程 ssh 命令。
# 用法：source env.sh   或   bash env.sh（仅打印）
a5_env_dump() {
  cat <<EOF
export HCCL_BUFFSIZE=${HCCL_BUFFSIZE}
export HCCL_NPU_SOCKET_PORT_RANGE="${HCCL_NPU_SOCKET_PORT_RANGE}"
export HCCL_OP_EXPANSION_MODE=${HCCL_OP_EXPANSION_MODE}
EOF
}

if [ "${BASH_SOURCE[0]}" = "${0:-}" ]; then
  source "$(dirname "$0")/lib.sh"; a5_load_config
  a5_info "远程测试会话内需注入的环境变量："
  a5_env_dump
else
  export HCCL_BUFFSIZE="${HCCL_BUFFSIZE:-4096}"
  export HCCL_NPU_SOCKET_PORT_RANGE="${HCCL_NPU_SOCKET_PORT_RANGE:-16000,17000}"
  export HCCL_OP_EXPANSION_MODE="${HCCL_OP_EXPANSION_MODE:-AIV}"
fi
