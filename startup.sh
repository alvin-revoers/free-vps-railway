#!/bin/bash

set -e

PORT=${PORT:-6080}
RESOLUTION=${RESOLUTION:-1280x720x24}
VNC_PASSWORD=${VNC_PASSWORD:-""}

echo "=================================================="
echo " Starting Free VPS (Ubuntu XFCE4 + noVNC)"
echo " Screen Resolution: $RESOLUTION"
echo " Web Port: $PORT"
echo " Clipboard: ENABLED"
echo "=================================================="

rm -f /tmp/.X0-lock
rm -f /tmp/.X11-unix/X0

# ==================================================
# 1. Xvfb
# ==================================================

echo "[1/4] Starting Xvfb..."

Xvfb :0 \
    -screen 0 "$RESOLUTION" \
    -ac \
    +extension GLX \
    +render \
    -noreset &

XVFB_PID=$!

sleep 2

# ==================================================
# 2. XFCE
# ==================================================

echo "[2/4] Starting XFCE..."

export DISPLAY=:0

dbus-launch \
    --exit-with-session \
    startxfce4 &

sleep 4

# ==================================================
# 3. x11vnc
# ==================================================

echo "[3/4] Starting x11vnc..."

if [ -n "$VNC_PASSWORD" ]; then

    mkdir -p /root/.vnc

    x11vnc \
        -storepasswd "$VNC_PASSWORD" /root/.vnc/passwd

    x11vnc \
        -display :0 \
        -rfbauth /root/.vnc/passwd \
        -forever \
        -shared \
        -rfbport 5900 \
        -clip xinerama \
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
        -clip xinerama \
        -noxdamage \
        -repeat \
        -cursor arrow \
        -bg \
        -o /var/log/x11vnc.log

fi

sleep 2

# ==================================================
# CHECK VNC
# ==================================================

if ! netstat -lnt 2>/dev/null | grep -q ":5900"; then
    echo "ERROR: x11vnc gagal listen pada port 5900"
    cat /var/log/x11vnc.log || true
    exit 1
fi

echo "x11vnc OK."

# ==================================================
# 4. noVNC
# ==================================================

echo "[4/4] Starting noVNC..."

exec /opt/novnc/utils/novnc_proxy \
    --vnc localhost:5900 \
    --listen 0.0.0.0:$PORT \
    --web /opt/novnc
