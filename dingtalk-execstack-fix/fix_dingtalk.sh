#!/usr/bin/env bash
# 修复 Ubuntu 26.04 上钉钉无法启动的问题
# 错误原因：钉钉的动态链接库（.so）带有可执行栈（execstack）标记，
# 而 Ubuntu 26.04 升级的 glibc 和内核由于安全原因默认拒绝可执行栈，导致程序崩溃。
# 修复路线：安装 patchelf 工具并清除有问题的动态链接库的可执行栈标记。

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请使用 sudo 运行此脚本: sudo $0"
    exit 1
fi

echo "开始修复钉钉在 Ubuntu 26.04 上的启动问题..."

# 安装必要的工具
echo "[1/3] 检查并安装 patchelf..."
if ! command -v patchelf &> /dev/null; then
    apt-get update && apt-get install -y patchelf
fi

DINGTALK_LIB_DIR="/opt/apps/com.alibabainc.dingtalk/files/Release"

# 检查钉钉是否安装
if [ ! -d "$DINGTALK_LIB_DIR" ]; then
    echo "错误：未找到钉钉安装目录 ($DINGTALK_LIB_DIR)。请确认钉钉已正确安装。"
    exit 1
fi

echo "[2/3] 正在清除动态链接库的可执行栈标记..."
TARGETS=("dingtalk_dll.so" "libconference_new.so")
FIX_COUNT=0

for lib in "${TARGETS[@]}"; 
do
    LIB_PATH="$DINGTALK_LIB_DIR/$lib"
    if [ -f "$LIB_PATH" ]; then
        echo "  -> 正在处理 $lib ..."
        # 清除可执行堆栈标记
        patchelf --clear-execstack "$LIB_PATH"
        if [ $? -eq 0 ]; then
            echo "     成功修复 $lib"
            FIX_COUNT=$((FIX_COUNT+1))
        else
            echo "     修复 $lib 失败，可能是权限不足。"
        fi
    else
        echo "  -> 警告：未找到文件 $LIB_PATH，跳过。"
    fi
done

echo "[3/3] 修复完成。"
if [ $FIX_COUNT -gt 0 ]; then
    echo "现在您可以尝试从应用菜单启动钉钉了！"
else
    echo "未修复任何文件。请确认钉钉是否最新版本或是否已修复。"
fi
