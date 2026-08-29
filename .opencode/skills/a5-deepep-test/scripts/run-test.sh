#!/usr/bin/env bash
# Phase 7：运行测试。HCCL 环境变量内联到远程 ssh 命令（不依赖会话）。
# 用法：bash run-test.sh --num-process 8 [--quant-type pertoken_fp8_e4m3] \
#                              [--visible-devices 0,1,2,3,4,5,6,7]
#   未给 --num-process 时用 config 的 A5_DEFAULT_NUM_PROCESS。
set -o pipefail
source "$(dirname "$0")/lib.sh"

a5_require_cmd ssh
a5_load_config

NUM_PROCESS="${A5_DEFAULT_NUM_PROCESS}"
QUANT_TYPE="${A5_QUANT_TYPE}"
VISIBLE_DEVICES="${A5_VISIBLE_DEVICES}"

while [ $# -gt 0 ]; do
  case "$1" in
    --num-process)      NUM_PROCESS="$2"; shift 2;;
    --quant-type)       QUANT_TYPE="$2"; shift 2;;
    --visible-devices)  VISIBLE_DEVICES="$2"; shift 2;;
    -h|--help) sed -n '2,5p' "$0"; exit 0;;
    *) a5_die "未知参数：$1";;
  esac
done

PROJ="$(a5_remote_project_path)"
ENV_PRE="export HCCL_BUFFSIZE=${HCCL_BUFFSIZE}; \
export HCCL_NPU_SOCKET_PORT_RANGE='${HCCL_NPU_SOCKET_PORT_RANGE}'; \
export HCCL_OP_EXPANSION_MODE=${HCCL_OP_EXPANSION_MODE}"
[ -n "${VISIBLE_DEVICES}" ] && ENV_PRE="${ENV_PRE}; export ASCEND_RT_VISIBLE_DEVICES='${VISIBLE_DEVICES}'"

a5_info "运行测试（$(a5_exec_target)）：${A5_TEST_SCRIPT} --num-process ${NUM_PROCESS} --quant-type ${QUANT_TYPE}"
a5_info "visible_devices=${VISIBLE_DEVICES:-<不限>}"
a5_run_remote "set -o pipefail; ${ENV_PRE}; cd '${PROJ}' && \
  python3 '${A5_TEST_SCRIPT}' --num-process '${NUM_PROCESS}' --quant-type '${QUANT_TYPE}'"
RC=$?
if [ "${RC}" -eq 0 ]; then a5_ok "测试通过"; else a5_warn "测试失败（看上方输出；常见原因：卡被占用/HCCL 端口冲突/wheel 架构不匹配）"; fi
a5_print_manual_cmd "${NUM_PROCESS}" "${QUANT_TYPE}" "${VISIBLE_DEVICES}"
exit "${RC}"
