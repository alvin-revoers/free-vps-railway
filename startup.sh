#!/bin/bash

set -e

PORT=${PORT:-6080}
RESOLUTION=${RESOLUTION:-1280x720x24}
VNC_PASSWORD=${VNC_PASSWORD:-""}

echo "=================================================="
echo " Free VPS - Ubuntu XFCE4 + x11vnc + noVNC"
echo " Screen Resolution: $RESOLUTION"
echo " Web Port: $PORT"
echo " Clipboard: ENABLED"
echo "=================================================="

# ==================================================
# CLEAN OLD DISPLAY
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

echo "[2/5] Starting XFCE..."

export DISPLAY=:0

dbus-launch \
    --exit-with-session \
    startxfce4 &

XFCE_PID=$!

sleep 5

echo "XFCE started."

# ==================================================
# 3. FORCE CLIPBOARD SUPPORT IN NOVNC
# ==================================================

echo "[3/5] Patching noVNC Clipboard..."

NOVNC="/opt/novnc"
VNC_HTML="$NOVNC/vnc.html"

if [ ! -f "$VNC_HTML" ]; then
    echo "ERROR: $VNC_HTML tidak ditemukan."
    exit 1
fi

# --------------------------------------------------
# Backup vnc.html
# --------------------------------------------------

if [ ! -f "$NOVNC/vnc.html.original" ]; then
    cp "$VNC_HTML" "$NOVNC/vnc.html.original"
fi

# --------------------------------------------------
# Pastikan tombol Clipboard ada
# --------------------------------------------------

if ! grep -q 'id="noVNC_clipboard_button"' "$VNC_HTML"; then

    echo "Clipboard button belum ada. Menambahkan..."

    python3 - <<'PY'
from pathlib import Path

p = Path("/opt/novnc/vnc.html")
s = p.read_text()

marker = '<!-- Toggle fullscreen -->'

button = '''
<!-- Forced Clipboard Button -->
<input type="image"
       alt="Clipboard"
       src="app/images/clipboard.svg"
       id="noVNC_clipboard_button"
       class="noVNC_button"
       title="Clipboard">

<div class="noVNC_crosscenter">
<div id="noVNC_clipboard" class="noVNC_panel">

<div class="noVNC_heading">
<img alt="" src="app/images/clipboard.svg">
Clipboard
</div>

<p class="noVNC_subheading">
Edit clipboard content in the textbox below.
</p>

<textarea id="noVNC_clipboard_text"
          rows="5"></textarea>

</div>
</div>

'''

if marker in s:
    s = s.replace(marker, button + marker)

p.write_text(s)
PY

fi

# --------------------------------------------------
# Pastikan Clipboard tidak disembunyikan oleh CSS
# --------------------------------------------------

CSS="$NOVNC/app/styles/base.css"

if [ -f "$CSS" ]; then

    if ! grep -q 'FORCE CLIPBOARD MOBILE' "$CSS"; then

        cat >> "$CSS" <<'EOF'

/* ==================================================
   FORCE CLIPBOARD MOBILE
   ================================================== */

#noVNC_clipboard_button {
    display: block !important;
    visibility: visible !important;
    opacity: 1 !important;
}

#noVNC_clipboard_button.noVNC_hidden {
    display: block !important;
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

    #noVNC_clipboard_button {
        display: block !important;
        visibility: visible !important;
        opacity: 1 !important;
        width: 35px !important;
        height: 35px !important;
    }

    #noVNC_clipboard_button img {
        display: block !important;
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

/* FORCE CLIPBOARD MOBILE */

EOF

    fi

fi

# ==================================================
# EXTRA JAVASCRIPT
# Force clipboard button visibility
# ==================================================

cat > "$NOVNC/clipboard-force.js" <<'EOF'

(function () {

    function forceClipboard() {

        const button =
            document.getElementById("noVNC_clipboard_button");

        const panel =
            document.getElementById("noVNC_clipboard");

        if (button) {

            button.classList.remove("noVNC_hidden");

            button.style.display = "block";
            button.style.visibility = "visible";
            button.style.opacity = "1";

        }

        if (panel) {

            panel.style.zIndex = "9999";

        }

    }

    // Immediately
    forceClipboard();

    // DOM may still be loading
    setTimeout(forceClipboard, 500);
    setTimeout(forceClipboard, 1500);
    setTimeout(forceClipboard, 3000);

    // Keep checking because noVNC changes classes
    setInterval(forceClipboard, 2000);

})();

EOF

# --------------------------------------------------
# Inject JS into vnc.html
# --------------------------------------------------

if ! grep -q 'clipboard-force.js' "$VNC_HTML"; then

    sed -i \
        's#</body>#<script src="clipboard-force.js"></script>\n</body>#' \
        "$VNC_HTML"

fi

echo "noVNC Clipboard patch OK."

# ==================================================
# 4. START x11vnc
# ==================================================

echo "[4/5] Starting x11vnc..."

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
# CHECK x11vnc
# ==================================================

if ! netstat -lnt 2>/dev/null | grep -q ":5900"; then

    echo "ERROR: x11vnc gagal listen pada port 5900"

    if [ -f /var/log/x11vnc.log ]; then
        cat /var/log/x11vnc.log
    fi

    exit 1
fi

echo "x11vnc OK - port 5900."

# ==================================================
# 5. START NOVNC
# ==================================================

echo "[5/5] Starting noVNC..."

echo "=================================================="
echo " noVNC: http://0.0.0.0:$PORT"
echo " VNC: localhost:5900"
echo " Clipboard: ENABLED + FORCED"
echo "=================================================="

exec /opt/novnc/utils/novnc_proxy \
    --vnc localhost:5900 \
    --listen 0.0.0.0:$PORT \
    --web "$NOVNC"
