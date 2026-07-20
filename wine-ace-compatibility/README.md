# Running legacy Wine applications on Ubuntu 26.04

This case study explains how a Spark Store build of **Yinxiang Biji
(Evernote China) 7.2.6** was made usable on Ubuntu 26.04 GNOME Wayland. The
same method applies to other legacy Wine packages wrapped by Spark
`spark-dwine-helper`, Deepin Wine, and the ACE/Bookworm compatibility
environment.

![Compatibility repair flow](compatibility-flow.svg)

## Scope and safety

This is a diagnostic playbook, not a universal installer. Apply the smallest
change that fixes the failing layer:

1. repair package state;
2. prove the sandbox failure before changing AppArmor;
3. add only capabilities shown in the audit log;
4. install the application's actual architecture dependencies;
5. resolve runtime/ABI ordering;
6. use software rendering only as an application-specific fallback.

Back up every system file before editing it. Package updates may replace
vendor launchers or ACE files, so keep changes reproducible and re-check them
after upgrades.

## Tested stack

| Layer | Tested component |
|---|---|
| Host | Ubuntu 26.04, GNOME Wayland |
| Store package | `com.evernote.spark 7.2.6.8111spark3` |
| Wine bridge | `deepin-wine6-stable-ace 6.0.0.68` |
| Container | Spark ACE, Debian Bookworm user space |
| Hardware | ThinkPad X1 Carbon Gen 13, recent Intel integrated GPU |

## Failure progression

### 1. The packages were not configured

`dpkg-query` showed the application as `install ok unpacked` and the bridge as
`install ok half-configured`. The application could not start because its Wine
bridge had never completed the ACE-side installation.

### 2. Ubuntu AppArmor blocked nested Bubblewrap

Spark's `bookworm-run` starts an ACE root filesystem through nested
Bubblewrap. Ubuntu's `unpriv_bwrap` AppArmor profile denied the inner
Bubblewrap request:

```text
apparmor="DENIED" profile="unpriv_bwrap"
comm="bwrap" capname="sys_admin"
```

Further configuration exposed narrowly scoped requirements: `chown`,
`dac_override`, `setgid`, `setuid`, `setpcap`, and `sys_ptrace`. They were
discovered from the audit log, not guessed.

### 3. Wine installed, but GLX creation failed

Wine reached `Evernote.exe`, then exited with:

```text
libGL error: No driver found
X Error ... X_GLXCreateContext
```

The Bookworm container's Mesa 22 stack did not recognize the recent Intel GPU.
The application was 32-bit, but only the 64-bit Mesa DRI stack was installed.

### 4. Adding i386 Mesa exposed an ABI collision

Installing `libgl1-mesa-dri:i386` provided `swrast_dri.so`, but Deepin Wine's
legacy `runtime-i386` placed an older `libm.so.6` ahead of Bookworm libraries:

```text
swrast_dri.so: version `GLIBC_2.29' not found
```

Completely disabling the legacy runtime was also incorrect: Deepin Wine then
lost its own `sys_msvcrt.dll.so` dependency chain. The working configuration
keeps the Deepin runtime but puts Bookworm's i386 glibc and Mesa first.

### 5. Fonts and application-local rendering fallback

The container also needed 32-bit FreeType and Fontconfig. Because its old Mesa
still could not drive this GPU directly, Yinxiang Biji was launched with
`llvmpipe`. The fallback was added only to this application's launcher.

## General layered solution

### Layer 0 — Collect evidence

Run the included read-only collector:

```bash
./collect-wine-compat-diagnostics.sh com.evernote.spark
```

Keep package state, architecture, wrapper chain, audit events, Wine output,
and graphics-loader output together. Do not fix the first warning you see:
Deepin tray D-Bus warnings, translated-folder warnings, and the fatal loader
error can appear in the same log.

### Layer 1 — Repair host package state

```bash
dpkg-query -W -f='${Package}\t${Status}\t${Version}\n' \
  com.evernote.spark deepin-wine6-stable-ace
sudo dpkg --configure -a
dpkg --audit
```

Both host packages must end in `install ok installed`.

### Layer 2 — Make the ACE sandbox start

```bash
bookworm-run true
journalctl -k --since "10 minutes ago" --no-pager |
  grep 'profile="unpriv_bwrap"'
```

If AppArmor denies a capability, back up the profile and add only capabilities
required by observed ACE operations. This case required:

```text
capability chown,
capability dac_override,
capability setgid,
capability setuid,
capability setpcap,
capability sys_ptrace,
capability sys_admin,
```

Reload and retest:

```bash
sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict
bookworm-run true
```

Do not replace the profile with an unrestricted rule. Requirements may change
with Ubuntu or Spark releases.

### Layer 3 — Complete the bridge inside ACE

```bash
bookworm-run /usr/bin/deepin-wine6-stable --version
sudo bookworm-run aptss install -y \
  libgl1-mesa-dri:i386 libglx-mesa0:i386 libgl1:i386 \
  libfreetype6:i386 libfontconfig1:i386
```

An unrelated service package may fail inside an unprivileged container.
Evaluate whether requested libraries were configured and whether the target
application needs that service; do not weaken the sandbox for an unused
daemon.

### Layer 4 — Resolve ABI and loader precedence

```bash
LIBGL_DEBUG=verbose WINEDEBUG=+seh,+loaddll ./application-launcher
bookworm-run ldd /usr/lib/i386-linux-gnu/dri/swrast_dri.so
```

For this stack the bridge must retain Deepin Wine's private libraries while
preferring Bookworm's i386 ABI:

```bash
export LD_LIBRARY_PATH="/usr/lib/i386-linux-gnu:/lib/i386-linux-gnu:$LD_LIBRARY_PATH"
export LIBGL_DRIVERS_PATH="/usr/lib/i386-linux-gnu/dri"
export WINELDPATH="/lib/ld-linux.so.2"
```

Test both sides: `swrast_dri.so` must load without a GLIBC error, while
`shell32.dll` and `sys_msvcrt.dll.so` must still load from Deepin Wine.

### Layer 5 — Select a rendering policy

Try native rendering first. If container Mesa is older than the GPU, use an
application-local fallback:

```bash
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
```

Do not put these variables in `/etc/environment`; that would disable hardware
acceleration for unrelated applications.

### Layer 6 — Validate behavior, not only exit codes

```bash
pgrep -af 'Evernote.exe|wineserver|services.exe|explorer.exe'
```

Then validate the visible window, text rendering, sign-in, network access,
note synchronization, clipboard, file chooser, and a clean second launch.

## Decision matrix

| Symptom | Evidence | Repair layer |
|---|---|---|
| Package is `unpacked` or `half-configured` | `dpkg-query`, `dpkg --audit` | Host package state |
| Namespace permission error | AppArmor audit entry for `bwrap` | Sandbox policy |
| Wine command absent in ACE | Container `wine --version` fails | Bridge installation |
| `X_GLXCreateContext` fails | `LIBGL_DEBUG=verbose` | Graphics architecture |
| `GLIBC_x.y not found` | Loader names old runtime path | ABI precedence |
| `sys_msvcrt.dll.so` missing | Wine `+loaddll` trace | Restore vendor runtime |
| Fonts are missing | Wine FreeType warning | i386 font libraries |
| Silent exit | Default `WINEDEBUG=-all` | Targeted Wine tracing |

## Included files

- `compatibility-flow.dot` — editable Graphviz source.
- `compatibility-flow.svg` and `.png` — rendered English diagrams for GitHub.
- `collect-wine-compat-diagnostics.sh` — read-only evidence collector.
- `deepin-wine6-stable-bookworm-wrapper.example` — loader-order example.
- `render-flow.sh` — reproducibly regenerates the images.

## Rollback

Restore backups of the application launcher, ACE Wine wrapper, and AppArmor
profile. Reload AppArmor after restoring its profile. Remove added i386
libraries only after checking dependencies with the ACE package manager.
