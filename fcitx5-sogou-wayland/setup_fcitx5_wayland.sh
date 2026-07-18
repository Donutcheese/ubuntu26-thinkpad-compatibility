#!/usr/bin/env bash
# 在 GNOME Wayland 下配置 Fcitx5 并使用搜狗词库
# 路线说明：
# 1. 放弃官方搜狗输入法Linux版，因为其高度依赖 X11，在 Wayland 下容易崩溃或无法呼出。
# 2. 采用 Fcitx5 框架，利用 scel2org5 和 libime_pinyindict 将搜狗的 .scel 词库提取并转换为二进制格式供 Fcitx5 使用。
# 3. 在 GNOME Wayland 中，输入法候选框容易出现显示 bug 或闪烁，安装官方推荐的 Kimpanel 扩展，通过 DBus 接管候选框原生渲染。

echo "开始配置 Fcitx5 和 Wayland 兼容性支持..."

# 1. 安装核心组件
echo "安装 Fcitx5 及中文组件..."
sudo apt-get update
sudo apt-get install -y fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk3 fcitx5-frontend-qt5 libime-bin fcitx5-config-qt

# 2. 设置环境变量
echo "配置环境变量..."
im-config -n fcitx5
grep -q "GTK_IM_MODULE=fcitx" ~/.profile || echo "export GTK_IM_MODULE=fcitx" >> ~/.profile
grep -q "QT_IM_MODULE=fcitx" ~/.profile || echo "export QT_IM_MODULE=fcitx" >> ~/.profile
grep -q "XMODIFIERS=@im=fcitx" ~/.profile || echo "export XMODIFIERS=@im=fcitx" >> ~/.profile

mkdir -p ~/.config/environment.d
cat > ~/.config/environment.d/fcitx.conf << 'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF

# 3. 设置开机自动启动 (对于 GNOME)
mkdir -p ~/.config/autostart
cp /usr/share/applications/org.fcitx.Fcitx5.desktop ~/.config/autostart/
if ! grep -q "X-GNOME-Autostart-enabled=true" ~/.config/autostart/org.fcitx.Fcitx5.desktop; then
    echo "X-GNOME-Autostart-enabled=true" >> ~/.config/autostart/org.fcitx.Fcitx5.desktop
fi

# 4. 解决 Wayland 候选框不显示的兼容性问题 (安装 Kimpanel 扩展)
echo "通过 DBus 安装 Kimpanel 扩展，接管 GNOME 的候选框渲染..."
gdbus call --session \
    --dest org.gnome.Shell.Extensions \
    --object-path /org/gnome/Shell/Extensions \
    --method org.gnome.Shell.Extensions.InstallRemoteExtension \
    "kimpanel@kde.org" || echo "请手动前往扩展中心安装 Kimpanel: kimpanel@kde.org"

echo "配置完成！请注销并重新登录以使所有设置生效。"
echo "如果您有搜狗词库 (.scel)，可以使用包含的 import_sogou_dict.sh 工具进行导入。"
