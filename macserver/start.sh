#!/bin/sh
# starts the whole mac server: data, llm, food, insights, voice, then the mail watcher and the discord bridge if setup.sh set them up, waiting for each one
# usage: ./start.sh   (Ctrl+C stops everything, and so does any one of them stopping)
# logs go to logs/<name>.log, the first run downloads the models so it takes a while
# HOST and PORT are cleared, each server has its own defaults (set them by running its own start script)
cd "$(dirname "$0")"
unset HOST PORT
mkdir -p logs
servers=""

stop() {
    trap - INT TERM EXIT
    echo "stopping"
    for s in $servers; do kill "${s#*:}" 2>/dev/null; done
    for s in $servers; do wait "${s#*:}" 2>/dev/null; done
}
trap stop EXIT
trap 'exit 1' INT TERM
caffeinate -is -w $$ &  # keeps the mac awake while this runs

ready() {
    case "$2" in
        http*) curl -fs -m 2 "$2" > /dev/null ;;
        *) grep -q "$2" "logs/$1.log" ;;
    esac
}

# name, address that answers when it is ready (or text its log prints, for ones with no address)
start() {
    "./$1/start_$1.sh" > "logs/$1.log" 2>&1 &
    pid=$!
    servers="$servers $1:$pid"
    printf "%s ... " "$1"
    until ready "$1" "$2"; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "failed, see logs/$1.log"
            exit 1
        fi
        sleep 2
    done
    echo "ready"
}

start data http://127.0.0.1:8001/health
start llm http://127.0.0.1:11434/v1/models
start food http://127.0.0.1:8002/health
start insights http://127.0.0.1:8004/insights/health
start voice http://127.0.0.1:8000/health
if [ -s config/email_accounts ]; then
    start mail http://127.0.0.1:8003/health
else
    echo "mail ... skipped, run ./setup.sh email to turn it on"
fi
if grep -qs '^DISCORD_ALLOWED_USERS=' config/bellai.env; then
    start discord "bell discord ready"
else
    echo "discord ... skipped, run ./setup.sh discord to turn it on"
fi
echo "all up, Ctrl+C to stop"

while :; do
    for s in $servers; do
        if ! kill -0 "${s#*:}" 2>/dev/null; then
            echo "${s%:*} stopped, see logs/${s%:*}.log"
            exit 1
        fi
    done
    sleep 5
done
