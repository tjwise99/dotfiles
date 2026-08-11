#!/bin/sh
# Compositor. Rofi draws its own rounded corners and needs an ARGB visual for
# the area outside them; without a compositor those corners render black.
#
# Skipped under virtualisation. QEMU is handed no video device by the NixOS VM
# runner, so the GPU is emulated and every composited frame is drawn on the
# CPU — enough to make the desktop unusable rather than merely slower, which is
# a worse trade than losing the corners. Switching the VM to -vga qxl was not
# enough on its own.
#
# This tests "am I virtualised", which is a proxy for "is there no hardware
# acceleration" — the same substitution the askpass block in shell/env.sh warns
# about, and it will be wrong on a VM with GPU passthrough. Kept because the
# direct test needs a GL query and a package installed to run it, and because
# being wrong here costs rounded corners rather than a broken session.
if systemd-detect-virt --quiet; then
    echo "picom: virtualised, compositor skipped" >&2
    exit 0
fi

pkill -x picom
while pgrep -x picom >/dev/null; do sleep 1; done
picom --config "$HOME/.config/picom.conf" >/tmp/picom.log 2>&1 &
