#!/usr/bin/env bash
# 修复 ThinkPad X1 Carbon 等机型在 GNOME 下 Fn 功能键（音量、亮度等）不工作的问题
# 错误原因：在 Ubuntu 26.04 中，GNOME 媒体快捷键服务 (gsd-media-keys) 启动时，
# PipeWire 音频服务可能尚未准备就绪。导致 gsd 报错 "Unable to get default sink" 并放弃接管媒体键。
# 修复路线：利用 systemd user 层的 override (覆盖配置)，强制指定 gsd-media-keys
# 必须在 pipewire-pulse 服务启动之后再启动，彻底消除竞态条件。

echo "开始修复 Fn 媒体按键竞态条件问题..."

# 创建 systemd user override 目录
SERVICE_DIR="$HOME/.config/systemd/user/org.gnome.SettingsDaemon.MediaKeys.service.d"
mkdir -p "$SERVICE_DIR"

# 写入 override 配置，增加启动依赖
cat > "$SERVICE_DIR/after-pipewire.conf" << 'EOF'
[Unit]
After=pipewire-pulse.service
Wants=pipewire-pulse.service
EOF

echo "已写入 systemd 启动顺序配置。"

# 重新加载 systemd 用户守护进程并重启服务
systemctl --user daemon-reload
systemctl --user restart org.gnome.SettingsDaemon.MediaKeys.service

echo "Fn 按键服务已重启！您现在可以直接使用 Fn 媒体键调节音量和亮度。"
echo ""
echo "【ThinkPad Fn-Lock 提示】"
echo "在 X1 Carbon 上，如果 Fn 键和 F1-F12 行为颠倒，您可以按 Fn + Esc 切换 Fn-Lock 模式。"
