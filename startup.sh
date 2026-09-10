#!/bin/bash

set -e

PORT=${PORT:-6080}
RESOLUTION=${RESOLUTION:-1280x720x24}
VNC_PASSWORD=${VNC_PASSWORD:-""}

NOVNC="/opt/novnc"

echo "=================================================="
echo " Starting Free VPS"
echo " Ubuntu XFCE4 + Xvfb + x11vnc + noVNC"
echo " Resolution : $RESOLUTION"
echo " Web Port   : $PORT"
echo " Clipboard  : ENABLED"
echo "=================================================="

# ==================================================
# CLEAN DISPLAY
# ==================================================

rm -f /tmp/.X0-lock
rm -f /tmp/.X11-unix/X0

mkdir -p /tmp/.X11-unix

# ==================================================
# 1. START XVFB
# ==================================================

echo "[1/5] Starting Xvfb..."

Xvfb :0 \
    -screen 0 "$RESOLUTION" \
    -ac \
    +extension GLX \
    +render \
    -noreset &

XVFB_PID=$!

sleep 2

if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    echo "ERROR: Xvfb gagal start."
    exit 1
fi

echo "Xvfb OK."

# ==================================================
# 2. START XFCE
# ==================================================

echo "[2/5] Starting XFCE4..."

export DISPLAY=:0

dbus-launch \
    --exit-with-session \
    startxfce4 &

sleep 5

echo "XFCE4 OK."

# ==================================================
# 3. PATCH NOVNC CLIPBOARD
# ==================================================

echo "[3/5] Patching noVNC clipboard..."

UI_JS="$NOVNC/app/ui.js"
BASE_CSS="$NOVNC/app/styles/base.css"

if [ ! -f "$UI_JS" ]; then
    echo "ERROR: $UI_JS tidak ditemukan."
    exit 1
fi

# --------------------------------------------------
# Backup original files
# --------------------------------------------------

if [ ! -f "$NOVNC/app/ui.js.original" ]; then
    cp "$UI_JS" "$NOVNC/app/ui.js.original"
fi

if [ ! -f "$NOVNC/app/styles/base.css.original" ]; then
    cp "$BASE_CSS" "$NOVNC/app/styles/base.css.original"
fi

# --------------------------------------------------
# IMPORTANT:
#
# noVNC menjalankan:
#
#     UI.updateClipboard();
#
# Fungsi ini dapat menyembunyikan tombol clipboard
# ketika browser Android mendukung Async Clipboard.
#
# Kita nonaktifkan pemanggilan tersebut supaya tombol
# clipboard tetap tersedia.
# --------------------------------------------------

python3 - <<'PY'
from pathlib import Path

p = Path("/opt/novnc/app/ui.js")

s = p.read_text()

old = "        UI.updateClipboard();"

new = """        // Clipboard fallback panel is intentionally kept enabled.
        // Do not call UI.updateClipboard() because that function
        // hides the clipboard button on browsers with Async Clipboard.
        // UI.updateClipboard();"""

if old in s:
    s = s.replace(old, new, 1)
    print("OK: UI.updateClipboard() disabled.")
else:
    print("INFO: UI.updateClipboard() call already patched or not found.")

p.write_text(s)
PY

# --------------------------------------------------
# FORCE BUTTON VISIBLE
# --------------------------------------------------

cat >> "$BASE_CSS" <<'EOF'

/* ==================================================
   FREE VPS - FORCE NOVNC CLIPBOARD BUTTON
   ================================================== */

#noVNC_control_bar #noVNC_clipboard_button {
    display: block !important;
    visibility: visible !important;
    opacity: 1 !important;
}

#noVNC_control_bar #noVNC_clipboard_button.noVNC_hidden {
    display: block !important;
    visibility: visible !important;
    opacity: 1 !important;
}

#noVNC_clipboard {
    z-index: 9999 !important;
}

#noVNC_clipboard_text {
    width: 360px !important;
    min-width: 150px !important;
    min-height: 120px !important;
    box-sizing: border-box !important;
}

@media (max-width: 600px) {

    #noVNC_control_bar #noVNC_clipboard_button {
        display: block !important;
        visibility: visible !important;
        opacity: 1 !important;
        width: 35px !important;
        height: 35px !important;
    }

    #noVNC_clipboard {
        max-width: calc(100vw - 80px) !important;
        max-height: calc(100vh - 80px) !important;
    }

    #noVNC_clipboard_text {
        width: calc(100vw - 120px) !important;
        max-width: 100% !important;
    }
}

/* END FREE VPS CLIPBOARD */

EOF

echo "noVNC clipboard patch OK."

# ==================================================
# 4. START X11VNC
# ==================================================

echo "[4/5] Starting x11vnc on port 5900..."

if [ -n "$VNC_PASSWORD" ]; then

    mkdir -p /root/.vnc

    x11vnc \
        -storepasswd \
        "$VNC_PASSWORD" \
        /root/.vnc/passwd

    x11vnc \
        -display :0 \
        -rfbauth /root/.vnc/passwd \
        -forever \
        -shared \
        -rfbport 5900 \
        -noxdamage \
        -repeat \
        -cursor arrow \
        -bg \
        -o /var/log/x11vnc.log

else

    x11vnc \
        -display :0 \
        -nopw \
        -forever \
        -shared \
        -rfbport 5900 \
        -noxdamage \
        -repeat \
        -cursor arrow \
        -bg \
        -o /var/log/x11vnc.log

fi

sleep 2

# ==================================================
# CHECK X11VNC
# ==================================================

if ! netstat -lnt 2>/dev/null | grep -q ":5900"; then

    echo "ERROR: x11vnc gagal listen di port 5900."

    if [ -f /var/log/x11vnc.log ]; then
        cat /var/log/x11vnc.log
    fi

    exit 1
fi

echo "x11vnc OK."

# ==================================================
# 5. START NOVNC
# ==================================================

echo "[5/5] Starting noVNC..."

echo "=================================================="
echo " noVNC     : $PORT"
echo " VNC       : localhost:5900"
echo " Clipboard : ENABLED"
echo "=================================================="

exec "$NOVNC/utils/novnc_proxy" \
    --vnc localhost:5900 \
    --listen 0.0.0.0:$PORT \
    --web "$NOVNC"
