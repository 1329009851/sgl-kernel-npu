#!/usr/bin/env bash
# Phase 2b：部署。重命名为 .zipa 规避传输限制 -> scp 上传 -> 远程清旧目录 -> 解压。
# 用法：bash deploy.sh [--zip <local-zip>]
set -o pipefail
source "$(dirname "$0")/lib.sh"

a5_require_cmd scp
a5_require_cmd ssh
a5_load_config
a5_check_ssh_batch 2>/dev/null | grep -q ok || \
  { a5_warn "免密未就绪，先跑 setup-ssh.sh"; exit 3; }

LOCAL_ZIP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --zip) LOCAL_ZIP="$2"; shift 2;;
    -h|--help) sed -n '2,3p' "$0"; exit 0;;
    *) a5_die "未知参数：$1";;
  esac
done

if [ "${LOCAL_ZIP}" = "" ] || [ ! -f "${LOCAL_ZIP}" ]; then
  SCRIPT_DIR="$(dirname "$0")"
  DEFAULT_ZIP="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/sgl-kernel-npu.zip"
  if [ -f "${DEFAULT_ZIP}" ]; then LOCAL_ZIP="${DEFAULT_ZIP}"; fi
fi
[ -f "${LOCAL_ZIP}" ] || a5_die "未找到本地 zip，请先 pack.sh 或用 --zip 指定"

STAGE="$(mktemp -d)"
ZIPA="${STAGE}/${A5_ZIP_NAME}.zipa"
a5_info "本地重命名为 .zipa 规避传输限制：${ZIPA##*/}"
cp "${LOCAL_ZIP}" "${ZIPA}"

REMOTE_ZIPA="${A5_REMOTE_HOME}/${A5_ZIP_NAME}.zipa"
REMOTE_ZIP="${A5_REMOTE_HOME}/${A5_ZIP_NAME}.zip"
REMOTE_PROJ="$(a5_remote_project_path)"

a5_info "上传 -> ${A5_USER}@${A5_HOST}:${REMOTE_ZIPA}"
a5_scp_up "${ZIPA}" "${REMOTE_ZIPA}" || a5_die "scp 上传失败"

a5_info "远程：清理旧目录 + 解压"
a5_ssh "
set -e
cd '${A5_REMOTE_HOME}' || exit 1
rm -rf '${REMOTE_PROJ}' '${REMOTE_ZIP}'
mv '${REMOTE_ZIPA}' '${REMOTE_ZIP}'
if command -v unzip >/dev/null 2>&1; then
  unzip -q '${REMOTE_ZIP}'
else
  python3 -c \"import zipfile,sys; zipfile.ZipFile('${REMOTE_ZIP}').extractall('.')\"
fi
rm -f '${REMOTE_ZIP}'
test -f '${REMOTE_PROJ}/build.sh' || { echo '解压后未找到 build.sh' >&2; exit 1; }
echo DEPLOY_OK
" || a5_die "远程解压/校验失败"

rm -rf "${STAGE}"
a5_ok "部署完成，远程项目：${REMOTE_PROJ}"
echo "${REMOTE_PROJ}"
