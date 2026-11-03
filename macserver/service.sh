#!/bin/sh
# runs the mac server in the background and starts it at login, using launchd
# usage: ./service.sh install [--anyway]|uninstall|restart|status|logs [name]
# install can be run again to pick up changes, and the whole set restarts if any one of them stops
cd "$(dirname "$0")"
here=$(pwd)
label=com.bellai.macserver
plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"  # a login session, which is what lets it use the keychain

case "$1" in
    install)
        command -v uv > /dev/null || { echo "missing uv (brew install uv)"; exit 1; }
        # macOS won't let a background job read these folders unless sh has Full Disk Access, so it would fail over and over
        case "$here" in
            "$HOME/Documents"/*|"$HOME/Desktop"/*|"$HOME/Downloads"/*|"$HOME/Library/Mobile Documents"/*)
                if [ "$2" != "--anyway" ]; then
                    echo "this folder is in one of the folders macOS protects (Documents, Desktop, Downloads or iCloud Drive),"
                    echo "so it can't be started in the background from here. Either:"
                    echo "  - put the repo somewhere else (for example git clone it to ~/BellAI) and run this from there, or"
                    echo "  - give /bin/sh Full Disk Access in System Settings > Privacy & Security, then run: ./service.sh install --anyway"
                    exit 1
                fi ;;
        esac
        case "$here" in *[\&\<\>]*) echo "this folder's path has a character launchd can't take, move it"; exit 1 ;; esac
        mkdir -p logs "$HOME/Library/LaunchAgents"
        # launchd starts with almost no PATH, so it gets the folder uv is in
        cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$here/start.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$here</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$(dirname "$(command -v uv)"):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>30</integer>
    <key>ExitTimeOut</key>
    <integer>30</integer>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$here/logs/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>$here/logs/launchd.log</string>
</dict>
</plist>
EOF
        plutil -lint "$plist" > /dev/null || exit 1
        launchctl bootout "$domain/$label" 2> /dev/null
        launchctl bootstrap "$domain" "$plist" || exit 1
        echo "installed, the servers are starting (./service.sh logs to watch, ./service.sh status to check)"
        ;;
    uninstall)
        launchctl bootout "$domain/$label" 2> /dev/null
        rm -f "$plist"
        echo "uninstalled, the servers are stopped and won't start at login"
        ;;
    restart)
        launchctl kickstart -k "$domain/$label" || { echo "not installed, run ./service.sh install"; exit 1; }
        echo "restarting"
        ;;
    status)
        info=$(launchctl print "$domain/$label" 2> /dev/null) || { echo "not installed"; exit 0; }
        echo "$info" | sed -nE 's/^[[:space:]]*(state|pid|last exit code) = /\1: /p'
        curl -fs -m 3 http://127.0.0.1:8000/health && echo || echo "voice server not answering yet"
        ;;
    logs)
        # launchd.log is this script's own, the others are one per server (data, llm, food, voice, mail, discord)
        tail -n 40 -f "logs/${2:-launchd}.log"
        ;;
    *)
        echo "usage: ./service.sh install [--anyway]|uninstall|restart|status|logs [name]"
        exit 1
        ;;
esac
