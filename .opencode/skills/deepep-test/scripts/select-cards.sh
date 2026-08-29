#!/usr/bin/env bash
# Phase 6：选卡。远程 npu-smi info 打印卡状态。
#   交互用法（人在终端）：bash select-cards.sh
#     脚本会读入卡号 -> 输出 num_process 与 visible_devices，供 run-test.sh 使用。
#   非交互：由 AI 代理跑本脚本拿 npu-smi 输出后，用 Question 工具问用户，
#           再把结果通过环境变量传给 run-test.sh。
# 用法：bash select-cards.sh [--print-only]
set -o pipefail
source "$(dirname "$0")/lib.sh"

a5_require_cmd ssh
a5_load_config

PRINT_ONLY=false
[ "${1:-}" = "--print-only" ] && PRINT_ONLY=true

a5_info "远程卡状态："
a5_ssh "npu-smi info" || a5_warn "npu-smi 不可用，可能非 root 或环境未就绪"

if ${PRINT_ONLY}; then exit 0; fi

if [ ! -t 0 ]; then
  a5_info "非交互环境：默认 num_process=${A5_DEFAULT_NUM_PROCESS}，visible_devices=${A5_VISIBLE_DEVICES:-<不限>}"
  echo "NUM_PROCESS=${A5_DEFAULT_NUM_PROCESS}"
  echo "VISIBLE_DEVICES=${A5_VISIBLE_DEVICES}"
  exit 0
fi

echo
echo "请输入要使用的卡号（逗号分隔，如 0,1,2,3,4,5,6,7），回车=不限制："
read -rp "卡号: " CARDS
echo "请输入 num-process（回车=用卡号数量或默认 ${A5_DEFAULT_NUM_PROCESS}）:"
read -rp "num-process: " NP

if [ -z "${NP}" ]; then
  if [ -n "${CARDS}" ]; then
    NP=$(echo "${CARDS}" | tr ',' '\n' | grep -c .)
  else
    NP="${A5_DEFAULT_NUM_PROCESS}"
  fi
fi

echo
echo "NUM_PROCESS=${NP}"
echo "VISIBLE_DEVICES=${CARDS}"
a5_warn "如需持久化，请把上述值写回 config.sh（A5_DEFAULT_NUM_PROCESS / A5_VISIBLE_DEVICES）"
