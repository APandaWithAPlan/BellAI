# BellAi Discord Bridge (Mac)

## Overview

**BellAi Discord Bridge** lets you talk to BellAI from Discord. A text message gets a reply from the [chat model](../llm/README.md), and a photo of a meal gets a nutrition summary from the [food model](../food/README.md), shown as an embedded message. `/mail` shows what the [mail watcher](../mail/README.md) found in your inbox, and `/reply` and `/email` draft emails for you to approve. The bot runs on this Mac and connects out to Discord, so no port needs to be opened.

Only the Discord user IDs you gave to `../setup.sh discord` get an answer, because the bot reaches your servers. It answers in a direct message, or in a server when it is @mentioned. Everyone else is ignored.

## Getting Started

### Prerequisites

* Software: `uv` (`brew install uv`). The script installs Python 3.11 and `discord.py` into `.venv`.
* Setup: Run `../setup.sh discord` first. It makes sure the bot token is in the keychain and your user ID is in `../config/bellai.env`.
* Discord: The bot must be added to a server you share with it, and **Message Content Intent** must be on for it in the Discord developer portal.
* Servers: The `llm` server on port `11434`, the `food` server on port `8002` for photos, and the `mail` server on port `8003` for `/mail`.

### How to Enable / Access

1. Run `./start_discord.sh` in this folder, or run `../start.sh`, which starts it with the other servers once setup has been done.
2. Wait for `bell discord ready` in the log.
3. Send the bot a direct message in Discord.

## How to Use It

1. **Chat:** Send any message. BellAI remembers the last 10 messages in each channel.
2. **Meal photo:** Attach a photo, with an optional note like "half portion" as the message text. The reply lists each food with its weight and calories, and the totals.
3. **Meal description:** Use `/food` with what you ate, like `2 eggs and toast`, and optionally a photo.
4. **Check your mail:** Use `/mail` to see the important emails from the last check, each with a number.
5. **Reply or write an email:** Use `/reply` with the number from `/mail` and what to say (`12`, `yes, Thursday works`), or `/email` with an address and what to say. BellAI shows a draft with **Send** and **Discard** buttons, and nothing is sent until you press Send. `/drafts` shows the ones still waiting, which is also how to get the buttons back after the bot restarts. The mail commands answer so only you can see them. All of this needs `../setup.sh email` and the mail watcher running.
6. **Start over:** Use `/reset` to make BellAI forget the conversation.
   Use `/purge` to also delete BellAI's last messages from the channel. It looks through the newest 200 messages and deletes only BellAI's own, so anything older stays, and it can't remove messages that only you can see, like mail replies.
7. **In a server:** @mention the bot at the start of the message, for example `@BellAI what's the weather like?`. Slash commands need no mention, and only the people on your list can use them.
8. **Handle an error:** If BellAI says its chat model, food model or mail watcher isn't running, start it with `../start.sh`. If the bot stays offline or the log says `PrivilegedIntentsRequired`, turn on Message Content Intent for the bot. If the slash commands don't show up, add the bot to the server again with the `applications.commands` scope ticked as well as `bot`. The log is `../logs/discord.log`.

> 💡 **Tip:** `/food` and photos are a stopgap. Food, health and home requests are meant to be recognized by the model itself, which will reply with embedded messages like the meal one.
