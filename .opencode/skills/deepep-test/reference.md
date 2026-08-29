# Deepep Test — 设计参考 / 排错 / 安全说明

本文件是 `SKILL.md` 的补充，记录设计取舍、典型故障与安全考量。

---

## 1. 与原始流程文档的映射

| 原始 `A5测试流程.docx` 步骤 | 本 skill 对应 |
|---|---|
| skill 目录存配置文件，记录环境信息/账号密码，ssh 免密，首次询问账号密码 | `templates/config.sh` + `setup-ssh.sh`（仅存环境/路径，密码不落盘） |
| 把 `sgl-kernel-npu.zip` 改名 `.zipa` 规避传输问题 → 传到 `/home/工号` → 旧目录先删 → 解压 | `pack.sh` + `deploy.sh` |
| 进 `sgl-kernel-npu` 跑 `bash build.sh -a deepep Ascend950` | `build-remote.sh` |
| 检查编译是否成功 | `build-remote.sh` 末尾校验 + 定位 wheel |
| `pip uninstall deep_ep` → `pip install ./output/{新 wheel}` | `install-wheel.sh` |
| 配 HCCL 环境变量（三项 export） | `env.sh`（参考）+ `run-test.sh` 内联 |
| `npu-smi info` 查卡，问用户用哪几张 | `select-cards.sh` + AI 代理用 Question 工具 |
| 跑 `python3 tests/python/deepep/test_intranode.py --num-process 8 --quant-type pertoken_fp8_e4m3` | `run-test.sh`（num-process 来自上一步） |

---

## 2. 关键设计取舍

### 2.1 为何不存密码（安全偏离说明）

原始文档要求"记录账号密码"。本 skill **不落盘密码**，改为：
- `config.sh` 只存 `A5_HOST / A5_USER / A5_EMPLOYEE_ID / 路径 / 参数`
- 首次用 `setup-ssh.sh` 跑 `ssh-copy-id`，密码经 `read -s` 读一次内存、用完即弃
- 之后全部 `ssh -o BatchMode=yes`，靠密钥免密

理由：明文密码入库违反最佳实践，且与"免密连接"目标自相矛盾。若团队强制凭据，请改用 OS 密钥环 / `ssh-agent`，**绝不**写明文到 `config.sh`。

### 2.2 `.zipa` 改名

仅为规避某些传输链路对 `.zip` 后缀的拦截，**不是加密**。流程：本地 `cp` 成 `.zipa` → `scp` → 远程 `mv` 回 `.zip` → `unzip`。临时文件放 `mktemp -d`，结束后清理。

### 2.3 环境变量为何内联而非 source

每次 `ssh` 都是新会话，`export` 不跨调用持久。所以 `run-test.sh` 把三个 HCCL 变量 + `ASCEND_RT_VISIBLE_DEVICES` 内联进同一条远程命令，保证对测试进程生效。`env.sh` 仅作本地参考/打印。

### 2.4 选卡与 num-process 的关系

原始文档"num-process 由上一步指定"——即 `--num-process` = 用户选定卡数。`select-cards.sh` 在交互模式下按卡号数量自动算 num-process；AI 代理编排时应先 `--print-only` 取 `npu-smi` 输出，再用 Question 工具问用户，最后把数字传给 `run-test.sh --num-process`。卡号经 `ASCEND_RT_VISIBLE_DEVICES` 限制。

### 2.5 Docker 执行环境（编译/安装/测试在容器内）

原始文档没提 Docker，但实测：A5 宿主机 base python（`/home/healthy_check/pkg/miniconda3`）**无 `torch`/`torch_npu`**，`build.sh` 在 `cmake/config_envs.cmake` 处直接 FATAL。真正带 torch_npu + pybind11 + CANN 的是 vllm-ascend 容器（Python 3.11，torch 2.10，cann-9.1.0）。故：

- `config.sh` 增 `A5_DOCKER=<容器名>`（留空=宿主机直接跑）
- `lib.sh` 提供 `a5_run_remote`：设了 `A5_DOCKER` 就 `ssh host "docker exec <c> bash -lc '<cmd>'"`，否则原样 `ssh host '<cmd>'`
- `build-remote.sh` / `install-wheel.sh` / `run-test.sh` 改用 `a5_run_remote`；`deploy.sh` 仍走宿主机（`/home` 挂载进容器，路径一致，宿主机解压后容器可见）
- 选容器：`docker ps` 看运行中的 vllm-ascend 容器；本次用 `deepep-test-container`

### 2.6 编译前注入代理（自动拉第三方库）

`build.sh` 编 ops 会 `git clone https://gitcode.com/cann/catlass.git` 取 tag `v1.6.1`（A5；A3 用 `catlass-v1-stable`），还可能拉其它第三方库。A5/容器直连 gitcode.com 多半超时。解法：在 `config.sh` 设 `A5_USE_PROXY=true` + `A5_HTTP_PROXY=...`，`lib.sh` 的 `a5_proxy_exports()` 生成 `export http_proxy/https_proxy/no_proxy/GIT_SSL_NO_VERIFY=true; `，`build-remote.sh` 把它拼到编译命令前（`bash -lc` 进容器后、`build.sh` 前），git clone 即走代理、跳过 SSL 校验。断网时改 `A5_USE_PROXY=false`，并用 §2.7 离线复用兜底。

### 2.7 catlass 离线复用（代理也不通时的兜底）

`ops/build.sh` 逻辑：若 `csrc/deepep/ops/third_party/catlass/.git` 在且 `HEAD == v1.6.1^{commit}`，则跳过联网（输出 "catlass is already at target ref"）。故可从主机上其它 checkout 拷贝一份 catlass（HEAD 须为 `48f7461a`，即 v1.6.1）到目标 `third_party/catlass`，并 `docker exec <c> git config --global --add safe.directory "*"` 避免 dubious ownership。详见 SKILL.md Phase 3。

---

## 3. 典型故障与排查

| 现象 | 排查 |
|---|---|
| `BatchMode` 连接失败 | 跑 `setup-ssh.sh`；检查 `~/.ssh` 权限 700、`authorized_keys` 600 |
| scp 卡住/被拦 | 已走 `.zipa`；仍失败换 `rsync -e 'ssh -p PORT'` 或分片 `split` |
| `build.sh` 失败 | 远程 `tail -100` 看日志；多为 CANN 版本/驱动不符或内存不足 |
| `cmake: No module named 'torch'` | 在宿主机 base python 跑了，缺 torch_npu；设 `A5_DOCKER=<容器>` 进容器编译 |
| `catlass fetch failed`（连不上 gitcode.com） | 设 `A5_USE_PROXY=true` + `A5_HTTP_PROXY` 走代理自动 clone；代理也不通则拷现成 catlass 到 `third_party/catlass`（HEAD=v1.6.1=48f7461a），见 §2.7 |
| `detected dubious ownership` | `docker exec <c> git config --global --add safe.directory "*"` |
| pip install 报 `invalid wheel` | 确认 wheel 是 `aarch64` 且匹配远程 Python 版本（`python3 -V`） |
| `import deep_ep` 失败 | `ldd` 查 `.so` 依赖；CANN 库 `LD_LIBRARY_PATH` 是否就绪 |
| HCCL 端口冲突 | 改 `HCCL_NPU_SOCKET_PORT_RANGE`，错开他人 |
| 测试报卡被占用 | `npu-smi info` 看占用进程；换卡或等释放 |
| `unzip` 远程缺失 | `deploy.sh` 已回退 `python3 zipfile` 解压 |

---

## 4. 3-Strike 协议（失败 escalation）

```
1: 看错误 → 定位 → 针对性修
2: 同错换法（换工具/清缓存/降参）
3: 重审假设（查版本/查权限/查占用）
>3: 向用户汇报已试方案 + 原始错误，请求指导
```

---

## 5. 前置依赖速查

**本地：** `ssh scp ssh-keygen`（必）；`ssh-copy-id`（可选，缺失回退）；`zip`（可选，缺失回退 `git archive`）；`git`（可选，定位项目根）。

**远程：** `bash python3 pip unzip npu-smi` + CANN 工具链；仓库自带 `build.sh` 与 `tests/python/deepep/test_intranode.py`。

---

## 6. 可扩展点

- 增加非 deepep 模块（如 `build.sh -a <other> Ascend950`）：改 `config.sh` 的 `A5_BUILD_TARGET` 与 `A5_TEST_SCRIPT`，其余脚本通用
- 多机分布式：扩展 `lib.sh` 的 host 列表，`select-cards.sh`/`run-test.sh` 改为循环多 host
- 结果归档：`run-test.sh` 成功后把日志 `scp` 回本地 `results/` 目录
