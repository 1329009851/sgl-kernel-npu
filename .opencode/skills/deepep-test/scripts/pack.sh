#!/usr/bin/env bash
# Phase 2a：打包 sgl-kernel-npu.zip。优先用现成 zip，否则从工作树打包。
# 用法：bash pack.sh [--project-dir <repo-root>] [--zip <out-path>]
# 输出：末行打印最终 zip 绝对路径。
set -o pipefail
source "$(dirname "$0")/lib.sh"

PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_ZIP=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2;;
    --zip) OUT_ZIP="$2"; shift 2;;
    -h|--help)
      sed -n '2,5p' "$0"; exit 0;;
    *) a5_die "未知参数：$1";;
  esac
done

[ -d "${PROJECT_DIR}" ] || a5_die "项目目录不存在：${PROJECT_DIR}"
[ "${OUT_ZIP}" = "" ] && OUT_ZIP="${PROJECT_DIR}/sgl-kernel-npu.zip"

if [ -f "${OUT_ZIP}" ]; then
  a5_ok "复用现成 zip：${OUT_ZIP}"
  echo "${OUT_ZIP}"
  exit 0
fi

a5_info "从工作树打包：${PROJECT_DIR} -> ${OUT_ZIP}"
EXCLUDE=( -x "*.git*" -x "output/*" -x "__pycache__/*" -x "*.opencode*" \
          -x "build/*" -x "*.pyc" -x "*.so" -x "*.zipa" )
if command -v zip >/dev/null 2>&1; then
  ( cd "${PROJECT_DIR}" && zip -rq "${OUT_ZIP}" . "${EXCLUDE[@]}" ) \
    || a5_die "zip 打包失败"
elif command -v git >/dev/null 2>&1 && [ -d "${PROJECT_DIR}/.git" ]; then
  a5_warn "无 zip，回退 git archive（仅含已提交内容，不含未跟踪文件）"
  git -C "${PROJECT_DIR}" archive --format=zip --prefix=sgl-kernel-npu/ \
    -o "${OUT_ZIP}" HEAD || a5_die "git archive 失败"
  OUT_ZIP="${OUT_ZIP%/}"
else
  a5_die "既无 zip 也无 git，无法打包。请先准备 sgl-kernel-npu.zip"
fi
[ -f "${OUT_ZIP}" ] || a5_die "打包产物未生成：${OUT_ZIP}"
a5_ok "打包完成：$(du -h "${OUT_ZIP}" | cut -f1)"
echo "${OUT_ZIP}"
