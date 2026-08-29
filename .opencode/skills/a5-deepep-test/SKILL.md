---
name: a5-deepep-test
description: A5（Ascend 950）服务器上 deepep 内核端到端测试流程。覆盖 SSH 免密部署、远程编译、安装 wheel、配置 HCCL 环境变量、选卡、运行 test_intranode.py。首次执行询问账号并配置免密登录。适用于 sgl-kernel-npu 在昇腾 NPU 卡上的回归/功能测试。
user-invocable: true
allowed-tools: "Read, Write, Edit, Bash, Glob, Grep, Question"
metadata:
  version: "1.0.0"
---

# A5 Deepep Test — A5 服务器 deepep 端到端测试流程

把本地 `sgl-kernel-npu` 源码打包 → 传到 A5（Ascend 950）服务器 → 编译 deepep → 安装 wheel → 配置 HCCL 环境变量 → 选卡 → 跑 `test_intranode.py`。

---

## 1. 概述

| 项 | 值 |
|----|----|
| 目标平台 | Ascend 950（A5 服务器） |
| 被测对象 | `sgl-kernel-npu` 仓库的 deepep 内核 |
| 测试入口 | `tests/python/deepep/test_intranode.py` |
| 远程工作目录 | `/home/<工号>/sgl-kernel-npu/` |
| 连接方式 | SSH 免密（密钥认证） |
| 默认测试参数 | `--num-process 8 --quant-type pertoken_fp8_e4m3` |

---

## 2. 何时使用

**适用：**
- 需要在 A5 服务器上对 sgl-kernel-npu 的 deepep 做端到端验证
- 改了 deepep 相关代码后做回归
- 验证新编译出的 wheel 在真实 NPU 卡上可跑通

**不适用：**
- 本地非 NPU 环境调试（无 Ascend 卡）
- 单元测试（请直接在仓库内跑 pytest）
- 非 deepep 模块（本流程脚本仅针对 deepep）

---

## 3. 目录结构

```
.opencode/skills/a5-deepep-test/
├── SKILL.md              # 本文件（设计文档）
├── reference.md          # 设计参考、排错、安全说明
├── templates/
│   └── config.sh         # 配置模板（首次运行拷到 config.sh）
└── scripts/
    ├── lib.sh            # 共享库：加载 config、ssh/scp 封装
    ├── setup-ssh.sh      # Phase 1：首次免密配置（ssh-copy-id）
    ├── pack.sh           # Phase 2a：打包 sgl-kernel-npu.zip
    ├── deploy.sh         # Phase 2b：传文件 + 远程清理 + 解压
    ├── build-remote.sh   # Phase 3：远程编译 + 检查产物
    ├── install-wheel.sh  # Phase 4：pip uninstall/install
    ├── env.sh            # Phase 5：HCCL 环境变量（可 source）
    ├── select-cards.sh   # Phase 6：npu-smi info + 选卡
    ├── run-test.sh       # Phase 7：运行 test_intranode.py
    └── a5-flow.sh        # 一键编排（按序跑全部 Phase）
```

> 配置文件 `config.sh`（由 `templates/config.sh` 拷贝而来）存放在 **skill 根目录**，记录主机/工号/路径/编译参数等环境信息。**不记录密码**（见 §7 安全）。

---

## 4. 配置管理

### 4.1 配置文件 `config.sh`

由 `templates/config.sh` 拷贝而来，bash 可直接 `source`。关键字段：

| 变量 | 含义 | 示例 |
|------|------|------|
| `A5_HOST` | A5 服务器 IP/主机名 | `192.168.1.10` |
| `A5_PORT` | SSH 端口 | `22` |
| `A5_USER` | 登录账号 | `hilt` |
| `A5_EMPLOYEE_ID` | 工号（决定远程目录 `/home/<工号>`） | `t12345` |
| `A5_REMOTE_HOME` | 远程家目录 | `/home/t12345` |
| `A5_PROJECT_DIR` | 远程项目目录名 | `sgl-kernel-npu` |
| `A5_ARCH` | 编译架构参数 | `Ascend950` |
| `A5_BUILD_TARGET` | 编译目标（build.sh -a） | `deepep` |
| `HCCL_BUFFSIZE` | HCCL 缓冲 | `4096` |
| `HCCL_NPU_SOCKET_PORT_RANGE` | HCCL 端口区间 | `"16000,17000"` |
| `HCCL_OP_EXPANSION_MODE` | HCCL 算子展开模式 | `AIV` |
| `A5_DEFAULT_NUM_PROCESS` | 默认进程数 | `8` |
| `A5_QUANT_TYPE` | 量化类型 | `pertoken_fp8_e4m3` |
| `A5_TEST_SCRIPT` | 测试脚本相对路径 | `tests/python/deepep/test_intranode.py` |
| `A5_SSH_KEY_SETUP` | 免密是否已配置 | `false`（首次） |
| `A5_DOCKER` | 编译/安装/测试执行的容器名；空=宿主机直接跑 | `zzx_deepep_test` |
| `A5_USE_PROXY` | 编译前是否注入代理（自动拉 catlass 等）；`true`/`false` | `true` |
| `A5_HTTP_PROXY` | 代理地址 | `http://141.3.216.104:30066` |
| `A5_NO_PROXY` | 代理排除列表 | `127.0.0.1,*.huawei.com,...` |
| `A5_GIT_SSL_NO_VERIFY` | git 跳过 SSL 校验（代理自签证书时） | `true` |

### 4.2 首次执行

首次运行任意脚本时，`lib.sh` 检测到 `config.sh` 不存在会：
1. 拷贝 `templates/config.sh` → `config.sh`
2. 提示用户补全 `A5_HOST / A5_USER / A5_EMPLOYEE_ID` 等字段后重跑
3. 若 `A5_SSH_KEY_SETUP=false`，引导执行 `setup-ssh.sh`（询问一次密码做 `ssh-copy-id`，之后免密）

> 原始流程文档要求"记录账号密码"。本 skill 出于安全考虑**改为密钥免密**：密码仅在首次 `ssh-copy-id` 时使用一次，不落盘。详见 `reference.md` §安全。

---

## 5. 前置条件

**本地（运行 opencode 的机器）：**
- `ssh` / `scp` 可用（Windows 10+ 自带 OpenSSH）
- `ssh-copy-id` 可用（Windows OpenSSH 较新版本自带；缺失时 `setup-ssh.sh` 回退到 `sshpass` 或手动提示）
- `zip` 可用（打包阶段需要；缺失时 `pack.sh` 回退到 `git archive` 或提示用现成 zip）
- `python`（仅 `lib.sh` 做 JSON/路径处理时可选）

**远程 A5 服务器：**
- `unzip`、`bash`、`npu-smi`、CANN 工具链（宿主机）
- `build.sh`（仓库自带）与 `tests/python/deepep/test_intranode.py`
- 至少一张可用 NPU 卡

**Docker 容器（编译/安装/测试实际执行处）：**
- A5(vllm-ascend) 宿主机 base python 无 `torch`/`torch_npu`，**编译必须在容器内**
- 容器需带 `python3`（含 torch / torch_npu / pybind11）、CANN、`npu-smi`
- 设 `config.sh` 的 `A5_DOCKER=<容器名>` 后，`build-remote.sh`/`install-wheel.sh`/`run-test.sh` 自动用 `docker exec` 进容器执行；`deploy.sh` 仍在宿主机（`/home` 通常挂载进容器，路径一致）
- 选容器：`ssh root@<host> 'docker ps --format "{{.Names}}\t{{.Image}}\t{{.Status}}"'`

---

## 6. 工作流程

```
Phase 1  setup-ssh.sh     首次免密配置（ssh-copy-id）
Phase 2a pack.sh         打包 sgl-kernel-npu.zip（或复用现成 zip）
Phase 2b deploy.sh       重命名为 .zipa → scp → 远程清旧目录 → 解压
Phase 3  build-remote.sh 远程 bash build.sh -a deepep Ascend950 + 检查产物
Phase 4  install-wheel.sh pip uninstall deep_ep → pip install ./output/<wheel>
Phase 5  env.sh          配置 HCCL_BUFFSIZE / SOCKET_PORT_RANGE / OP_EXPANSION_MODE
Phase 6  select-cards.sh npu-smi info → 询问用户选哪些卡
Phase 7  run-test.sh     python3 test_intranode.py --num-process N --quant-type ...
```

### Phase 1 — SSH 免密配置

```bash
bash .opencode/skills/a5-deepep-test/scripts/setup-ssh.sh
```
- 若 `~/.ssh/id_ed25519` 不存在，先生成
- 询问一次 `A5_USER@A5_HOST` 密码，执行 `ssh-copy-id`
- 成功后把 `config.sh` 的 `A5_SSH_KEY_SETUP` 置为 `true`
- 校验：`ssh -o BatchMode=yes A5_USER@A5_HOST echo ok`

### Phase 2a — 打包

```bash
bash scripts/pack.sh [--project-dir <repo-root>] [--zip <path>]
```
- 优先用现成 `sgl-kernel-npu.zip`（项目根或 `--zip` 指定）
- 否则从工作树打包：`zip -r` 排除 `.git/ output/ __pycache__/ .opencode/`
- 产物路径写到 stdout 末行，供 `deploy.sh` 使用

### Phase 2b — 部署

```bash
bash scripts/deploy.sh [--zip <path>]
```
按原始流程规避传输限制：
1. 本地把 zip 复制重命名为 `sgl-kernel-npu.zipa`（放临时目录）
2. `scp` 上传到 `$A5_REMOTE_HOME/`
3. 远程：若 `$A5_REMOTE_HOME/sgl-kernel-npu` 已存在 → `rm -rf` 再解压
4. 远程：`mv sgl-kernel-npu.zipa sgl-kernel-npu.zip && unzip -q && rm`
5. 校验远程 `$A5_REMOTE_HOME/sgl-kernel-npu/build.sh` 存在

### Phase 3 — 远程编译

```bash
bash scripts/build-remote.sh
```
- 设了 `A5_DOCKER` 则在容器内 `cd sgl-kernel-npu && bash build.sh -a deepep Ascend950`，否则宿主机
- `A5_USE_PROXY=true` 时编译命令前自动注入 `http_proxy/https_proxy/no_proxy/GIT_SSL_NO_VERIFY`，让 build.sh 能联网拉第三方库
- 捕获退出码，非 0 即失败并打印日志末 50 行
- 成功后定位 `output/` 下新编出的 deepep wheel（`*deep_ep*.whl`），路径写到 stdout

> **第三方库 catlass（gitcode.com）两种取法**：build.sh 编 ops 时 `git clone https://gitcode.com/cann/catlass.git` 取 `v1.6.1`（A5）。
> 1. **代理（推荐，自动）**：设 `A5_USE_PROXY=true` + `A5_HTTP_PROXY`，build.sh 走代理直接 clone。
> 2. **离线复用（断网兜底）**：从主机已有 checkout 拷一份到 `csrc/deepep/ops/third_party/catlass`，HEAD 须 == v1.6.1 commit(48f7461a)，build.sh 判定 "already at target ref" 跳过联网：
> ```bash
> ssh root@<host> 'cp -r /home/<其它工号>/sgl-kernel-npu/csrc/deepep/ops/third_party/catlass \
>   /home/<工号>/sgl-kernel-npu/csrc/deepep/ops/third_party/catlass && \
>   chown -R root:root /home/<工号>/sgl-kernel-npu/csrc/deepep/ops/third_party/catlass && \
>   docker exec <容器> git config --global --add safe.directory "*"'
> ```
> 查找现成 catlass：`find /home -maxdepth 8 -type d -name catlass 2>/dev/null`

### Phase 4 — 安装 wheel

```bash
bash scripts/install-wheel.sh [--wheel <remote-rel-path>]
```
- 在容器内 `python3 -m pip uninstall -y deep_ep`（失败不致命）
- `python3 -m pip install ./output/<wheel>`（wheel 路径来自 Phase 3）
- 校验：`python3 -c "import deep_ep"` 打印 `IMPORT_OK`

### Phase 5 — 配置环境变量

```bash
bash scripts/env.sh            # 打印应导出的变量
source scripts/env.sh         # 本地 source（仅参考用，远程不跨会话）
```
三个核心变量（写到远程测试会话内联，见 Phase 7）：

```bash
export HCCL_BUFFSIZE=4096
export HCCL_NPU_SOCKET_PORT_RANGE="16000,17000"
export HCCL_OP_EXPANSION_MODE=AIV
```

### Phase 6 — 选卡

```bash
bash scripts/select-cards.sh
```
- 远程 `npu-smi info` 打印卡状态
- **AI 代理应在此步用 Question 工具询问用户**：使用哪几张卡 / 几张卡
- 用户答复后，卡数 = `--num-process`；卡号写入 `ASCEND_RT_VISIBLE_DEVICES`（如 `0,1,2,3,4,5,6,7`）
- 若用户不指定，回落 `config.sh` 的 `A5_DEFAULT_NUM_PROCESS`，卡号不限制

### Phase 7 — 运行测试

```bash
bash scripts/run-test.sh --num-process 8 [--quant-type pertoken_fp8_e4m3] [--visible-devices 0,1,2,3,4,5,6,7]
```
远程单条命令（环境变量内联，不依赖会话）：

```bash
ssh A5_USER@A5_HOST \
  "export HCCL_BUFFSIZE=4096; \
   export HCCL_NPU_SOCKET_PORT_RANGE='16000,17000'; \
   export HCCL_OP_EXPANSION_MODE=AIV; \
   export ASCEND_RT_VISIBLE_DEVICES='0,1,2,3,4,5,6,7'; \
   cd $A5_REMOTE_HOME/sgl-kernel-npu && \
   python3 tests/python/deepep/test_intranode.py --num-process 8 --quant-type pertoken_fp8_e4m3"
```

> **测试完成后**，`run-test.sh` 会自动打印一条可复制的手动复现命令（按 `config.sh` 当前值生成：`A5_DOCKER` 非空则包 `docker exec -it <容器> bash -lc '...'`，否则 `bash -lc '...'`），方便人工在 A5 上复验。实现见 `lib.sh` 的 `a5_print_manual_cmd`。

### 一键编排

```bash
bash scripts/a5-flow.sh [--num-process N] [--skip-pack] [--skip-build]
```
按 Phase 1→7 顺序执行；缺 `--num-process` 时在 Phase 6 交互式询问。

---

## 7. 安全注意事项

- **不落盘密码**。密码仅在 `setup-ssh.sh` 首次 `ssh-copy-id` 时通过 `read -s` 读入，用完即弃
- `config.sh` 只存主机/工号/路径/参数，不含任何凭据
- 若团队强制要存凭据，建议用 OS 密钥环或 `ssh-agent`，**绝不**写明文密码到 `config.sh`
- `.zipa` 重命名仅为规避传输链路对 `.zip` 的拦截，不是加密手段
- 测试涉及多卡 HCCL，端口区间 `16000,17000` 需保证不与他人冲突

详见 `reference.md`。

---

## 8. 错误处理（3-Strike 协议）

| 失败点 | 第 1 次 | 第 2 次 | 第 3 次 |
|--------|--------|--------|--------|
| scp 传输 | 检查网络/端口 | 重试 `.zipa` 重传 | 换 `rsync -e ssh` 或分片 |
| build.sh | 看远程日志末 50 行 | 清 `output/` 重编 | 检查 CANN/驱动版本 |
| pip install | 看 pip 报错 | `pip cache purge` 重装 | 确认 wheel 架构匹配（aarch64） |
| test_intranode | 看 assertion | 降 `--num-process` 复跑 | `npu-smi info` 查卡是否被占 |

连续 3 次失败：向用户汇报已尝试方案 + 具体错误，请求指导。

---

## 9. 脚本速查

| 脚本 | 作用 | 关键参数 |
|------|------|---------|
| `setup-ssh.sh` | 首次免密 | — |
| `pack.sh` | 打包 zip | `--project-dir` `--zip` |
| `deploy.sh` | 传 + 解压 | `--zip` |
| `build-remote.sh` | 远程编译 | — |
| `install-wheel.sh` | 装 wheel | `--wheel` |
| `env.sh` | 打印/导出变量 | — |
| `select-cards.sh` | 查卡 | — |
| `run-test.sh` | 跑测试 | `--num-process` `--quant-type` `--visible-devices` |
| `a5-flow.sh` | 一键全流程 | `--num-process` `--skip-pack` `--skip-build` |
