#!/usr/bin/env bash
# 一键编排：Phase 1->7 按序执行。
# 用法：bash flow.sh [options]
#   --num-process N        直接指定进程数，跳过交互选卡
#   --visible-devices x,y  直接指定卡号
#   --skip-pack            复用现成 sgl-kernel-npu.zip，不重新打包
#   --skip-build           远端已有编译产物，跳过 Phase 3/4
#   --skip-ssh             假定免密已配好，跳过 Phase 1
#   --from <phase>         从指定 phase 开始（2|3|4|5|6|7）
set -o pipefail
source "$(dirname "$0")/lib.sh"

NUM_PROCESS=""
VISIBLE_DEVICES=""
SKIP_PACK=false
SKIP_BUILD=false
SKIP_SSH=false
FROM=1
while [ $# -gt 0 ]; do
  case "$1" in
    --num-process)      NUM_PROCESS="$2"; shift 2;;
    --visible-devices) VISIBLE_DEVICES="$2"; shift 2;;
    --skip-pack)  SKIP_PACK=true; shift;;
    --skip-build) SKIP_BUILD=true; shift;;
    --skip-ssh)   SKIP_SSH=true; shift;;
    --from)       FROM="$2"; shift 2;;
    -h|--help) sed -n '2,8p' "$0"; exit 0;;
    *) a5_die "未知参数：$1";;
  esac
done

a5_load_config

phase() { echo; echo "============ Phase $1: $2 ============"; }
S="${A5_SCRIPTS_DIR}"

if [ "${FROM}" -le 1 ] && ! ${SKIP_SSH}; then
  phase 1 "SSH 免密配置"
  "${S}/setup-ssh.sh" || a5_warn "免密未就绪，后续步骤可能失败"
fi

ZIP_PATH=""
if [ "${FROM}" -le 2 ]; then
  if ! ${SKIP_PACK}; then
    phase 2a "打包"
    ZIP_PATH=$("${S}/pack.sh" | tail -1) || a5_die "打包失败"
  else
    ZIP_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/sgl-kernel-npu.zip"
    [ -f "${ZIP_PATH}" ] || a5_die "--skip-pack 但找不到 ${ZIP_PATH}"
  fi
  phase 2b "部署"
  "${S}/deploy.sh" --zip "${ZIP_PATH}" >/dev/null || a5_die "部署失败"
fi

WHEEL_REL=""
if [ "${FROM}" -le 3 ] && ! ${SKIP_BUILD}; then
  phase 3 "远程编译"
  WHEEL_REL=$("${S}/build-remote.sh" | tail -1) || a5_die "编译失败"
  phase 4 "安装 wheel"
  "${S}/install-wheel.sh" --wheel "${WHEEL_REL}" || a5_die "安装 wheel 失败"
fi

if [ "${FROM}" -le 5 ]; then
  phase 5 "环境变量（内联到测试命令）"
  "${S}/env.sh"
fi

if [ -z "${NUM_PROCESS}" ]; then
  phase 6 "选卡"
  "${S}/select-cards.sh" --print-only
  if [ -t 0 ]; then
    "${S}/select-cards.sh" || true
    a5_warn "请把上面输出的 NUM_PROCESS/VISIBLE_DEVICES 通过 --num-process/--visible-devices 重跑，或写回 config.sh"
    exit 0
  else
    a5_info "非交互：用默认 num_process=${A5_DEFAULT_NUM_PROCESS}，visible_devices=${A5_VISIBLE_DEVICES:-<不限>}"
    NUM_PROCESS="${A5_DEFAULT_NUM_PROCESS}"; VISIBLE_DEVICES="${A5_VISIBLE_DEVICES}"
  fi
fi

phase 7 "运行测试"
RT_ARGS=( --num-process "${NUM_PROCESS}" --quant-type "${A5_QUANT_TYPE}" )
[ -n "${VISIBLE_DEVICES}" ] && RT_ARGS+=( --visible-devices "${VISIBLE_DEVICES}" )
"${S}/run-test.sh" "${RT_ARGS[@]}" || a5_die "测试失败"
a5_ok "全流程完成"
