# A5 Deepep Test — 配置模板
# 拷贝到 skill 根目录命名为 config.sh 后按实际环境填写。
# 首次运行任意脚本时 lib.sh 会自动拷贝本文件。
# 注意：本文件不记录任何密码，仅存环境/路径/参数。

# ---- 连接信息 ----
A5_HOST="192.168.1.10"          # A5 服务器 IP 或主机名
A5_PORT="22"                     # SSH 端口
A5_USER="hilt"                   # 登录账号
A5_EMPLOYEE_ID="t12345"          # 工号，决定远程目录 /home/<工号>

# ---- 远程路径 ----
A5_REMOTE_HOME="/home/${A5_EMPLOYEE_ID}"
A5_PROJECT_DIR="sgl-kernel-npu"  # 远程项目目录名
A5_ZIP_NAME="sgl-kernel-npu"     # 传输出于规避目的会改名为 .zipa

# ---- 编译参数 ----
A5_ARCH="Ascend950"              # build.sh 的架构参数
A5_BUILD_TARGET="deepep"         # build.sh -a 的目标
A5_BUILD_CMD="bash build.sh -a ${A5_BUILD_TARGET} ${A5_ARCH}"

# ---- HCCL 环境变量 ----
HCCL_BUFFSIZE="4096"
HCCL_NPU_SOCKET_PORT_RANGE="16000,17000"
HCCL_OP_EXPANSION_MODE="AIV"

# ---- 测试参数 ----
A5_TEST_SCRIPT="tests/python/deepep/test_intranode.py"
A5_DEFAULT_NUM_PROCESS="8"
A5_QUANT_TYPE="pertoken_fp8_e4m3"
# 选卡阶段若用户指定卡号，会写入 ASCEND_RT_VISIBLE_DEVICES；留空=不限制
A5_VISIBLE_DEVICES=""

# ---- 状态标记 ----
A5_SSH_KEY_SETUP="false"        # setup-ssh.sh 成功后改为 true

# ---- Docker 执行环境 ----
# 留空=直接在宿主机执行编译/安装/测试；填容器名=在 docker exec <name> 内执行
# A5(vllm-ascend) 容器内才带 torch_npu/pybind11/CANN，编译必须进容器
A5_DOCKER=""                     # 例：zzx_deepep_test

# ---- 代理（编译前自动下载第三方库，如 catlass from gitcode.com）----
# A5_USE_PROXY=true 时 build-remote.sh 会在编译命令前注入以下 export
# 断网时改 false，并用 reference.md §2.6 的 catlass 离线复用兜底
A5_USE_PROXY="false"
A5_HTTP_PROXY="http://141.3.216.104:30066"
A5_HTTPS_PROXY="${A5_HTTP_PROXY}"
A5_NO_PROXY="127.0.0.1,*.huawei.com,localhost,local,.local,inhuawei.com"
A5_GIT_SSL_NO_VERIFY="true"
