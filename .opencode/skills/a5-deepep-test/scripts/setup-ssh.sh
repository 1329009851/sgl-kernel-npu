#!/usr/bin/env bash
# Phase 1：首次免密配置。生成密钥（如缺）+ ssh-copy-id（询问一次密码，不落盘）。
# 用法：bash setup-ssh.sh
set -o pipefail
source "$(dirname "$0")/lib.sh"

a5_require_cmd ssh
a5_load_config

if [ "${A5_SSH_KEY_SETUP}" = "true" ]; then
  if a5_check_ssh_batch 2>/dev/null | grep -q ok; then
    a5_ok "免密已配置且可用，跳过。"
    exit 0
  fi
  a5_warn "config 标记已配置但 BatchMode 连接失败，重新配置。"
fi

KEY="${HOME}/.ssh/id_ed25519"
if [ ! -f "${KEY}" ] && [ ! -f "${HOME}/.ssh/id_rsa" ]; then
  a5_info "生成 ed25519 密钥（无 passphrase）"
  ssh-keygen -t ed25519 -N "" -f "${KEY}" >/dev/null || a5_die "ssh-keygen 失败"
fi
[ -f "${KEY}" ] || KEY="${HOME}/.ssh/id_rsa"
[ -f "${KEY}" ] || a5_die "找不到 SSH 私钥"

TARGET="${A5_USER}@${A5_HOST}"
a5_info "目标：${TARGET}（端口 ${A5_PORT}）"

if command -v ssh-copy-id >/dev/null 2>&1; then
  a5_info "执行 ssh-copy-id，请输入远程密码（仅此一次）："
  if [ "${A5_PORT}" = "22" ]; then
    ssh-copy-id -o StrictHostKeyChecking=accept-new "${TARGET}"
  else
    ssh-copy-id -p "${A5_PORT}" -o StrictHostKeyChecking=accept-new "${TARGET}"
  fi
else
  a5_warn "无 ssh-copy-id，回退到手动方式。请输入远程密码以追加公钥："
  PUB="$(cat "${KEY}.pub")"
  read -rsp "Password for ${TARGET}: " PWD; echo
  # 用 ssh 直接追加公钥（密码会再问一次）
  ssh -p "${A5_PORT}" -o StrictHostKeyChecking=accept-new "${TARGET}" \
    "umask 077; mkdir -p ~/.ssh; grep -qxF '${PUB}' ~/.ssh/authorized_keys 2>/dev/null || echo '${PUB}' >> ~/.ssh/authorized_keys"
fi

if a5_check_ssh_batch 2>/dev/null | grep -q ok; then
  a5_ok "免密配置成功。"
  sed -i.bak 's/^A5_SSH_KEY_SETUP=.*/A5_SSH_KEY_SETUP="true"/' "${A5_CONFIG}" 2>/dev/null || true
  exit 0
else
  a5_die "免密验证失败，请检查密码/主机/端口或远程 ~/.ssh 权限"
fi
