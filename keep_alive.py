"""
Keep-Alive Script for Free VPS / Web Container
Pings the public URL periodically to prevent the container from sleeping/idling.
"""

import urllib.request
import time
import datetime
import sys

# Replace with your actual Railway / Render / PaaS public URL
TARGET_URL = sys.argv[1] if len(sys.argv) > 1 else "https://free-vps-railway-production-0067.up.railway.app/"
INTERVAL_SECONDS = int(sys.argv[2]) if len(sys.argv) > 2 else 120  # Ping every 2 minutes

def ping_server(url):
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "VPS-KeepAlive-Bot/1.0"}
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            print(f"[{now}] Ping OK -> {url} (Status: {resp.status})")
            return True
    except Exception as e:
        print(f"[{now}] Ping Failed -> {url} (Error: {e})")
        return False

def main():
    print("==================================================")
    print(" VPS Keep-Alive Monitor")
    print(f" Target URL: {TARGET_URL}")
    print(f" Interval  : {INTERVAL_SECONDS} seconds")
    print("==================================================")
    
    while True:
        ping_server(TARGET_URL)
        time.sleep(INTERVAL_SECONDS)

if __name__ == "__main__":
    main()
