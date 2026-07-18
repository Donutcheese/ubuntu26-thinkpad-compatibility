#!/usr/bin/env bash
# 修复 Ubuntu 26.04 上外置 U 盘无法打开、USB 无线鼠标频繁断连的问题
# 错误原因：
# 1) U 盘：Ventoy/Windows 未安全弹出后 NTFS 带 dirty 脏标志；Ubuntu 26 默认用内核 ntfs3，
#    遇到 dirty 直接拒挂，图形界面报 “wrong fs type / bad superblock” 笼统错误。
# 2) 鼠标：ASUS ROG OMNI 接收器 (0b05:1ace) 被 USB autosuspend 休眠后枚举失败，表现为频繁断连。
# 修复路线：
# - 仅新增专用 udev / udisks 配置与脚本，不改内核参数、GRUB 及其它无关系统文件。
# - 可移动 NTFS U 盘插入时优先 ntfsfix -d 清 dirty；udisks 优先 ntfs-3g 并允许 ntfs3 force。
# - 仅对 ROG OMNI 接收器关闭 USB 自动休眠。
# Windows 侧可选脚本见同目录 Clear-UsbNtfsDirty.ps1（默认不改 Windows 系统文件）。

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请使用 sudo 运行此脚本: sudo $0"
    exit 1
fi

echo "开始修复 Ubuntu 26.04 USB NTFS / 无线鼠标问题..."

echo "[1/4] 检查并安装 ntfs-3g（若缺失）..."
if ! command -v ntfsfix &> /dev/null; then
    apt-get update && apt-get install -y ntfs-3g
fi

echo "[2/4] 安装仅针对可移动 NTFS 的 dirty 清理脚本与 udev 规则..."
cat > /usr/local/sbin/ntfs-usb-clear-dirty << 'EOF'
#!/bin/bash
# 仅处理：可移动块设备 + NTFS。不做格式化、不改分区表、不动系统盘。
set -euo pipefail

DEV="${1:-}"
[[ "$DEV" =~ ^[a-z]+[0-9]+$ ]] || exit 0
PATH_DEV="/dev/$DEV"
[[ -b "$PATH_DEV" ]] || exit 0

REMOVABLE_PARENT="/sys/block/${DEV%%[0-9]*}/removable"
[[ -f "$REMOVABLE_PARENT" ]] || exit 0
[[ "$(cat "$REMOVABLE_PARENT")" == "1" ]] || exit 0

FSTYPE="$(blkid -o value -s TYPE "$PATH_DEV" 2>/dev/null || true)"
[[ "$FSTYPE" == "ntfs" ]] || exit 0

if command -v ntfsfix >/dev/null 2>&1; then
  ntfsfix -d "$PATH_DEV" >/dev/null 2>&1 || true
fi
exit 0
EOF
chmod 755 /usr/local/sbin/ntfs-usb-clear-dirty

cat > /etc/udev/rules.d/99-ntfs-usb-clear-dirty.rules << 'EOF'
# 仅：USB 可移动分区 + NTFS。插入时优先清 dirty，不影响其它盘/文件系统
ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}=="ntfs", RUN+="/usr/local/sbin/ntfs-usb-clear-dirty %k"
EOF

echo "[3/4] 写入 udisks2 NTFS 挂载策略（仅覆盖 NTFS）..."
cat > /etc/udisks2/mount_options.conf << 'EOF'
# 仅覆盖 NTFS 挂载策略；其它文件系统不写即保持发行版默认
[defaults]
# 优先 ntfs-3g（对 dirty 更宽容），失败再试内核 ntfs3
ntfs_drivers=ntfs,ntfs3
# ntfs3 允许 force，避免图形界面再次弹出笼统错误
ntfs:ntfs3_defaults=uid=$UID,gid=$GID,force
ntfs:ntfs3_allow=uid=$UID,gid=$GID,umask,dmask,fmask,iocharset,discard,nodiscard,sparse,nosparse,hidden,nohidden,sys_immutable,nosys_immutable,showmeta,noshowmeta,prealloc,noprealloc,hide_dot_files,nohide_dot_files,windows_names,nocase,case,force
EOF

echo "[4/4] 安装仅针对 ROG OMNI 接收器的禁休眠规则..."
cat > /etc/udev/rules.d/99-rog-omni-no-autosuspend.rules << 'EOF'
# 仅匹配 ASUS ROG OMNI RECEIVER (0b05:1ace)，不影响其他 USB 设备
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0b05", ATTR{idProduct}=="1ace", TEST=="power/control", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0b05", ATTR{idProduct}=="1ace", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0b05", ATTR{idProduct}=="1ace", TEST=="power/autosuspend_delay_ms", ATTR{power/autosuspend_delay_ms}="-1"
EOF

udevadm control --reload
udevadm trigger --action=add --subsystem-match=usb --attr-match=idVendor=0b05 --attr-match=idProduct=1ace 2>/dev/null || true

# 若当前已插入该接收器，立即生效
for d in /sys/bus/usb/devices/*; do
  if [[ -f "$d/idVendor" && -f "$d/idProduct" ]]; then
    if [[ "$(cat "$d/idVendor")" == "0b05" && "$(cat "$d/idProduct")" == "1ace" ]]; then
      echo on > "$d/power/control" 2>/dev/null || true
      echo -1 > "$d/power/autosuspend" 2>/dev/null || true
      echo -1 > "$d/power/autosuspend_delay_ms" 2>/dev/null || true
      echo "  -> 已对当前插入的 ROG OMNI 立即禁用 autosuspend: $d"
    fi
  fi
done

systemctl reload udisks2 2>/dev/null || systemctl restart udisks2 2>/dev/null || true

echo "修复完成。"
echo "请拔插一次 U 盘验证能否直接打开；重新插入鼠标接收器验证是否还会频繁断连。"
echo "Windows 双系统可选脚本：同目录 Clear-UsbNtfsDirty.ps1（手动复制到 Windows 运行）。"
