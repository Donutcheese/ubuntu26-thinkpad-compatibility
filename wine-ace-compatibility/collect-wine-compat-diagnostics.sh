#!/usr/bin/env bash
set -u

package_name="${1:-com.evernote.spark}"
bridge_package="${2:-deepin-wine6-stable-ace}"

section() {
    printf '\n== %s ==\n' "$1"
}

section "Host"
. /etc/os-release
printf 'OS: %s; kernel: %s\n' "$PRETTY_NAME" "$(uname -r)"
printf 'Session: %s / %s\n' "${XDG_CURRENT_DESKTOP:-unknown}" "${XDG_SESSION_TYPE:-unknown}"

section "Package state"
dpkg-query -W -f='${Package}\t${Status}\t${Version}\n' \
    "$package_name" "$bridge_package" 2>&1 || true
dpkg --audit 2>&1 || true

section "Application desktop entry"
grep -R -E '^(Name|Exec)=' \
    /usr/share/applications/"$package_name".desktop \
    "$HOME/.local/share/applications/$package_name.desktop" 2>/dev/null || true

section "ACE boundary"
if command -v bookworm-run >/dev/null 2>&1; then
    timeout 15s bookworm-run true 2>&1 || true
    timeout 15s bookworm-run /usr/bin/deepin-wine6-stable --version 2>&1 || true
else
    echo "bookworm-run not found"
fi

section "Relevant AppArmor audit events"
journalctl -k --since "15 minutes ago" --no-pager 2>/dev/null |
    grep -E 'apparmor="DENIED".*(bwrap|wine)|profile="unpriv_bwrap"' |
    tail -n 80 || true

section "Graphics"
lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true
find /usr/lib -maxdepth 5 -path '*/dri/*_dri.so' -print 2>/dev/null |
    sort | head -n 80

section "Running Wine processes"
pgrep -af 'wine(server|loader)?|services.exe|explorer.exe|Evernote.exe' || true

cat <<'EOF'

This collector is read-only. Re-run the failing launcher separately with:
  LIBGL_DEBUG=verbose WINEDEBUG=+seh,+loaddll <launcher>
Review the output before changing security or loader configuration.
EOF
