# Ubuntu 26.04 兼容性问题修复与优化 (Lenovo ThinkPad)

*English version is below.*

本项目收集了在最新的 **Ubuntu 26.04 (Resolute Raccoon) GNOME Wayland** 环境下，**Lenovo ThinkPad X1 Carbon Gen 13** 等相关机型常遇到的一些兼容性问题的技术解决方案。

## 目录结构与问题说明

### 1. Fcitx5 搜狗输入法与 Wayland 候选框兼容问题 (`fcitx5-sogou-wayland/`)
**问题：** Ubuntu 26.04 默认的 Wayland 环境下，官方搜狗输入法 (基于 X11 架构) 存在严重的崩溃或无法呼出问题。而使用 Fcitx5 时，GNOME 经常会把弹出式候选框阻挡，导致可以输入拼音却看不见选字框。
**技术路线：** 
- 完全弃用陈旧的官方客户端，改为使用现代化的 `fcitx5`。
- 利用 `scel2org5` 和 `libime_pinyindict` 两个工具，将提取的搜狗 `.scel` 词库文件直接编译成 `Fcitx5` 的底层二进制词典 `.dict`，实现词库的完美移植。
- **核心修复：** 安装 Fcitx 作者开发的官方 GNOME 扩展 `Kimpanel`。该扩展通过 D-Bus 接口接管了 Fcitx5 的候选框渲染。由于它作为 GNOME 原生扩展运行，绕过了 Wayland 对第三方弹出窗口的限制，彻底解决了选字框不出现或闪烁的 Bug。

### 2. 钉钉 (DingTalk) 无法启动问题 (`dingtalk-execstack-fix/`)
**问题：** 在 Ubuntu 26.04 等使用了更新版本 glibc 和 Linux 内核的系统上，新内核对内存安全性有更严格的要求。由于钉钉某些闭源的 C/C++ 动态链接库 (`dingtalk_dll.so` 等) 在编译时没有清除“可执行堆栈”(Executable Stack) 标记，系统会为了安全原因拒绝加载它，导致钉钉启动秒退。
**技术路线：**
- 使用 ELF 二进制修改工具 `patchelf`。
- 扫描钉钉目录下的动态库，通过 `patchelf --clear-execstack <file.so>` 指令，直接在二进制层面擦除 ELF 头部的 `PT_GNU_STACK` 可执行标记。
- 去除标记后，glibc 将允许安全加载，从而修复启动崩溃问题。

### 3. ThinkPad Fn 媒体快捷键失效问题 (`thinkpad-fn-keys-fix/`)
**问题：** 在重启系统或刚登录后，键盘顶部的音量加减、亮度调节等 Fn 快捷键完全不工作。
**技术路线：**
- 经过调试发现这是 `systemd` 在启动用户会话时的**竞态条件 (Race Condition)**。
- 处理 GNOME 媒体键的守护进程 `gsd-media-keys` 启动得比 `pipewire-pulse` 音频服务还要早。`gsd-media-keys` 试图获取默认音频输出设备时失败报错 `Unable to get default sink`，从而放弃处理音量键。
- **修复：** 在 `~/.config/systemd/user/` 中建立一个 override 配置文件，利用 `After=pipewire-pulse.service` 显式强制定义依赖关系。这能确保在音频服务准备就绪前，按键接管程序暂缓启动，从根源消除竞态。

---

# Ubuntu 26.04 Compatibility Fixes (Lenovo ThinkPad)

This repository provides technical solutions for common compatibility issues encountered on **Ubuntu 26.04 (Resolute Raccoon) GNOME Wayland**, specifically tested on the **Lenovo ThinkPad X1 Carbon Gen 13**.

## Directories & Technical Explanations

### 1. Fcitx5 Sogou Wayland Candidate Box Fix (`fcitx5-sogou-wayland/`)
**Issue:** The official Sogou Input Method client relies heavily on legacy X11 and frequently crashes on Wayland. While Fcitx5 is a great alternative, GNOME Wayland's strict popup window management often causes the Fcitx5 candidate box to randomly disappear or fail to render.
**Technical Approach:** 
- Discard the legacy client and use the modern `fcitx5` framework.
- Use `scel2org5` and `libime_pinyindict` to parse Sogou's `.scel` dictionary files and compile them natively into Fcitx5 binary `.dict` formats.
- **Core Fix:** Install the `Kimpanel` GNOME extension (developed by the Fcitx author). It takes over the rendering of the candidate box via D-Bus. As a native GNOME Shell component, it bypasses Wayland's third-party popup restrictions, completely resolving the invisible candidate box bug.

### 2. DingTalk Startup Crash Fix (`dingtalk-execstack-fix/`)
**Issue:** Ubuntu 26.04 features updated glibc and kernels with stricter memory security enforcements. Certain closed-source dynamic libraries shipped with DingTalk (like `dingtalk_dll.so`) were compiled with the "Executable Stack" flag enabled. The OS denies loading these insecure libraries, causing an immediate crash on launch.
**Technical Approach:**
- Utilize `patchelf`, a utility for modifying existing ELF executables and libraries.
- Execute `patchelf --clear-execstack <file.so>` against the offending libraries to scrub the `PT_GNU_STACK` executable flag from the ELF headers.
- Once cleared, the system's dynamic loader allows execution without triggering security violations.

### 3. ThinkPad Fn Media Keys Fix (`thinkpad-fn-keys-fix/`)
**Issue:** Volume, mute, and brightness Fn keys fail to respond upon logging into the GNOME session.
**Technical Approach:**
- Investigation revealed a **race condition** in the `systemd` user session.
- The GNOME media keys daemon (`gsd-media-keys`) starts before the `pipewire-pulse` audio server is fully initialized. When `gsd-media-keys` tries to find the default sink to bind the volume keys, it fails (`Unable to get default sink`) and drops the key bindings.
- **Fix:** We inject a `systemd` user service override configuration using `After=pipewire-pulse.service`. This explicitly forces the media key daemon to wait for the audio subsystem to spin up first, completely eliminating the race condition.
