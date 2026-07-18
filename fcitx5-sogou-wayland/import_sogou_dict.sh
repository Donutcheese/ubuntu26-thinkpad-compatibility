#!/usr/bin/env bash

# Check if file path is provided
if [ -z "$1" ]; then
    echo "使用方法: $0 <sogou_dictionary.scel>"
    exit 1
fi

SCEL_FILE="$1"

# Check if file exists
if [ ! -f "$SCEL_FILE" ]; then
    echo "错误: 文件 '$SCEL_FILE' 不存在。"
    exit 1
fi

# Check for required tools
if ! command -v scel2org5 &> /dev/null; then
    echo "错误: 未找到 'scel2org5' 工具。请先安装 'fcitx5-chinese-addons'。"
    exit 1
fi

if ! command -v libime_pinyindict &> /dev/null; then
    echo "错误: 未找到 'libime_pinyindict' 工具。请先安装 'libime-bin'。"
    exit 1
fi

# Get base name without path and extension
BASENAME=$(basename "$SCEL_FILE" .scel)
TEMP_TXT=$(mktemp /tmp/sogou_dict_XXXXXX.txt)
DICT_DIR="$HOME/.local/share/fcitx5/pinyin/dictionaries"
DICT_OUT="$DICT_DIR/$BASENAME.dict"

mkdir -p "$DICT_DIR"

echo "正在解析搜狗词库文件: $SCEL_FILE ..."
if scel2org5 "$SCEL_FILE" > "$TEMP_TXT" 2>/dev/null; then
    echo "正在转换为 Fcitx 5 二进制词库: $DICT_OUT ..."
    if libime_pinyindict "$TEMP_TXT" "$DICT_OUT"; then
        echo "成功！搜狗词库已成功导入至 Fcitx 5。"
        echo "词库文件已存放在: $DICT_OUT"
        
        # Clean up temp file
        rm -f "$TEMP_TXT"

        echo "正在重启 fcitx5 以应用词库更改..."
        killall fcitx5
        sleep 1
        fcitx5 -d
        echo "重启完成。您可以在 Fcitx 5 配置的“拼音 -> 词库管理”中查看新导入的词库。"
    else
        echo "错误: 转换二进制词库失败。"
        rm -f "$TEMP_TXT"
        exit 1
    fi
else
    echo "错误: 解析 scel 文件失败。"
    rm -f "$TEMP_TXT"
    exit 1
fi
