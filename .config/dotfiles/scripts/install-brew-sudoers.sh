#!/bin/bash
# Let the unattended 04:00 Homebrew cask upgrade (homebrew-update.sh) run the root
# commands casks need (removing root-owned old app files, pkg installers, uninstall
# scripts) without a password. Run once per Mac, in front of the screen:
#   bash ~/.config/dotfiles/scripts/install-brew-sudoers.sh
#
# Trade-off (accepted deliberately): xargs/rm without a password make this effectively
# root for any process running as this user. The password itself is never stored.
# A cask that needs a command outside this list still fails and is reported to Discord
# by `dotfiles converge`; add it here only after looking at what it runs.
set -euo pipefail
user="$(id -un)"
target=/etc/sudoers.d/homebrew-unattended
rule="$(mktemp)"
trap 'rm -f "$rule"' EXIT
cat >"$rule" <<EOF
# Managed by ~/.config/dotfiles/scripts/install-brew-sudoers.sh
# brew calls 'sudo -A -E', so SETENV is required alongside NOPASSWD.
Cmnd_Alias BREW_CASK = /usr/bin/xargs, /bin/rm, /bin/rmdir, /bin/mkdir, /bin/mv, /bin/cp, \\
    /bin/chmod, /usr/sbin/chown, /usr/bin/chflags, /usr/bin/ditto, /usr/sbin/installer, \\
    /usr/sbin/pkgutil, /bin/launchctl, /usr/bin/killall, /usr/bin/pkill, \\
    /Library/Application\\ Support/org.pqrs/*/scripts/uninstall/*.sh
${user} ALL=(root) NOPASSWD:SETENV: BREW_CASK
EOF
/usr/sbin/visudo -cf "$rule" >/dev/null
sudo /usr/bin/install -m 0440 -o root -g wheel "$rule" "$target"
sudo /usr/sbin/visudo -c >/dev/null
echo "Installed $target"
sudo -k
if sudo -n -E /usr/bin/xargs -0 -- /bin/rm -- </dev/null; then
  echo "OK: password-less sudo works for the Homebrew cask commands"
else
  echo "Rule installed but the check failed; review $target" >&2
  exit 1
fi
