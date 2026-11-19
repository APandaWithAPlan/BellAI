#!/bin/sh
set -eu
cd "$(dirname "$0")"
which=${1:-both}
runs=${2:-3}
export UDID=${UDID:-$(xcrun simctl list devices booted | grep -o '[0-9A-F-]\{36\}' | head -1)}
[ -n "$UDID" ] || { echo "No booted simulator, boot one first."; exit 1; }
bid=${BID:-com.nicholascervantes.bellaiios.app}
small=qwen3.5:4b-q4_K_M
big=qwen3.8:27b-q4_K_M

run() {
    for n in $(seq 1 "$runs"); do
        echo "== $1 run $n of $runs ($2)"
        xcrun simctl terminate "$UDID" "$bid" > /dev/null 2>&1 || true
        sleep 1
        xcrun simctl spawn "$UDID" defaults write "$bid" server.host -string 127.0.0.1
        xcrun simctl spawn "$UDID" defaults write "$bid" server.port.chat -int 11444
        xcrun simctl spawn "$UDID" defaults write "$bid" server.port.voice -int 8000
        xcrun simctl spawn "$UDID" defaults write "$bid" server.port.data -int 8011
        xcrun simctl launch "$UDID" "$bid" > /dev/null
        sleep 8
        mkdir -p "seeded/runs/$1/$n"
        python3 qwen_agent.py "$2" "seeded/runs/$1/$n" | tee "seeded/runs/$1/$n/console.txt"
    done
}

case "$which" in
    small) run small "$small" ;;
    big) run big "$big" ;;
    both) run small "$small"; run big "$big" ;;
    *) echo "Usage: ./run_qwen.sh [small|big|both] [runs]"; exit 1 ;;
esac
