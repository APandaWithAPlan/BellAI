#!/bin/sh
# first time setup for the mac server: checks the tools, then walks through connecting discord and email
# usage: ./setup.sh [discord|email]   (no argument does both, safe to run again, a blank answer skips)
# secrets (bot token, email app passwords) go in the macOS keychain, everything else in config/ (not in git)
cd "$(dirname "$0")"
CONFIG=config/bellai.env
ACCOUNTS=config/email_accounts  # one line per account: address imap-server smtp-server

say() { printf '\n== %s\n' "$1"; }

# question, default -> answer in $REPLY
ask() {
    printf '%s%s: ' "$1" "${2:+ [$2]}"
    read -r REPLY || { echo; echo "no answer, stopping"; exit 1; }
    REPLY=${REPLY:-$2}
}

# same, but nothing shows while typing
ask_secret() {
    printf '%s: ' "$1"
    stty -echo 2>/dev/null
    read -r REPLY || { stty echo 2>/dev/null; echo; echo "no answer, stopping"; exit 1; }
    stty echo 2>/dev/null
    echo
}
trap 'stty echo 2>/dev/null; exit 1' INT
trap 'stty echo 2>/dev/null' EXIT

# key, value -> config/bellai.env
set_var() {
    mkdir -p config && chmod 700 config
    touch "$CONFIG" && chmod 600 "$CONFIG"
    grep -v "^$1=" "$CONFIG" > "$CONFIG.tmp"
    printf '%s=%s\n' "$1" "$2" >> "$CONFIG.tmp"
    mv "$CONFIG.tmp" "$CONFIG" && chmod 600 "$CONFIG"
}

# service, account, secret -> keychain (read back to make sure it stuck)
# security -i takes the command from stdin, so the secret never shows up in the process list
save_secret() {
    printf 'add-generic-password -U -s "%s" -a "%s" -w "%s"\n' "$1" "$2" "$3" | security -i > /dev/null 2>&1
    [ "$(security find-generic-password -s "$1" -a "$2" -w 2> /dev/null)" = "$3" ]
}

prereqs() {
    say "Checking tools"
    for tool in uv curl security; do
        command -v "$tool" > /dev/null || { echo "missing $tool (install uv with: brew install uv)"; exit 1; }
    done
    # being on tailscale is the login for the app, so the phone can't reach this mac without it
    [ -d /Applications/Tailscale.app ] || command -v tailscale > /dev/null || echo "Tailscale isn't installed here, install it and name this Mac ai-server (brew install --cask tailscale-app)"
    echo "ok"
}

discord() {
    say "Discord"
    cat <<'EOF'
BellAI answers in Discord through a bot you own. In a browser:
  1. Go to https://discord.com/developers/applications and press New Application.
  2. Open Bot, press Reset Token and copy the token.
  3. On the same page, turn on Message Content Intent. Without it the bot can't read your messages.
  4. Open OAuth2 > URL Generator, tick bot and applications.commands, then tick Send Messages, Read Message History and
     Embed Links. Open the link it makes to add the bot to your server.
EOF
    while :; do
        ask_secret "Paste the bot token (blank to skip)"
        token=$REPLY
        [ -z "$token" ] && { echo "skipped Discord"; return; }
        # -H @- reads the header from stdin, so the token stays out of the process list
        name=$(printf 'Authorization: Bot %s\n' "$token" | curl -fs -m 10 -H @- https://discord.com/api/v10/users/@me \
            | sed -n 's/.*"username": *"\([^"]*\)".*/\1/p')
        [ -n "$name" ] && break
        echo "Discord didn't accept that token, try again."
    done
    echo "Connected as $name."

    cat <<'EOF'

Only the people you list can talk to BellAI, because it can act on this Mac.
In Discord, open Settings > Advanced and turn on Developer Mode, then right-click your name and press Copy User ID.
EOF
    while :; do
        ask "Your Discord user ID (separate several with spaces)"
        printf '%s' "$REPLY" | grep -Eq '^[0-9]{15,25}( [0-9]{15,25})*$' && break
        echo "That doesn't look like a user ID, it should be a long number."
    done

    save_secret bellai-discord bot "$token" || { echo "couldn't save the token to the keychain"; exit 1; }
    set_var DISCORD_BOT_NAME "$name"
    set_var DISCORD_ALLOWED_USERS "$REPLY"
    echo "Saved. The token is in the keychain as bellai-discord."
}

email() {
    say "Email"
    cat <<'EOF'
BellAI reads your mail with an app password, never your real one. Make one here:
  Gmail     turn on 2-Step Verification, then https://myaccount.google.com/apppasswords
  iCloud    https://account.apple.com > Sign-In and Security > App-Specific Passwords
  Outlook   https://account.microsoft.com/security > Advanced security options > App passwords
BellAI only reads mail on its own. It asks you before it sends anything.
EOF
    added=0
    while :; do
        echo
        ask "Email address (blank to finish)"
        [ -z "$REPLY" ] && break
        address=$REPLY
        case "${address##*@}" in
            gmail.com|googlemail.com) imap=imap.gmail.com smtp=smtp.gmail.com ;;
            icloud.com|me.com|mac.com) imap=imap.mail.me.com smtp=smtp.mail.me.com ;;
            outlook.com|hotmail.com|live.com) imap=outlook.office365.com smtp=smtp.office365.com ;;
            *) ask "IMAP server (for example imap.example.com)"; imap=$REPLY
               ask "SMTP server (for example smtp.example.com)"; smtp=$REPLY ;;
        esac
        ask_secret "App password"
        password=$(printf '%s' "$REPLY" | tr -d ' ')  # google shows them with spaces
        # listing the mailboxes is a login test, and -K - keeps the password out of the process list
        if ! printf 'user = "%s:%s"\n' "$address" "$password" | curl -fs -m 20 -K - "imaps://$imap/" > /dev/null; then
            echo "Couldn't sign in to $imap. Check the address and app password, then try again."
            continue
        fi
        save_secret bellai-email "$address" "$password" || { echo "couldn't save the password to the keychain"; exit 1; }
        mkdir -p config && chmod 700 config
        touch "$ACCOUNTS" && chmod 600 "$ACCOUNTS"
        grep -v "^$address " "$ACCOUNTS" > "$ACCOUNTS.tmp"
        echo "$address $imap $smtp" >> "$ACCOUNTS.tmp"
        mv "$ACCOUNTS.tmp" "$ACCOUNTS" && chmod 600 "$ACCOUNTS"
        echo "Connected $address."
        added=$((added + 1))
    done
    [ "$added" -eq 0 ] && { echo "skipped email"; return; }

    while :; do
        ask "Check for new mail every how many minutes" 10
        printf '%s' "$REPLY" | grep -Eq '^[0-9]+$' && [ "$REPLY" -ge 1 ] && break
        echo "Enter a whole number of minutes."
    done
    set_var EMAIL_CHECK_MINUTES "$REPLY"
    echo "Saved. Passwords are in the keychain as bellai-email."
}

case "${1:-all}" in
    discord) prereqs; discord ;;
    email) prereqs; email ;;
    all) prereqs; discord; email ;;
    *) echo "usage: ./setup.sh [discord|email]"; exit 1 ;;
esac

say "Done"
[ -f "$CONFIG" ] && sed 's/^/  /' "$CONFIG"
[ -f "$ACCOUNTS" ] && sed 's/^/  email: /' "$ACCOUNTS"
echo "Start the servers with ./start.sh"
