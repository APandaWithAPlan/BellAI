# BellAi Mail Watcher (Mac)

## Overview

**BellAi Mail Watcher** checks your inboxes every few minutes and has the [chat model](../llm/README.md) say what matters in each new email: how important it is, a one sentence summary, what you need to do, and any deadline. You can then ask for the important ones from Discord with `/mail` instead of opening your mail, and have BellAI write a reply or a new email for you to approve.

Everything stays on this Mac. Emails go only to the local chat model, and only the sender, subject, date and the model's notes are saved, never the email itself. The watcher opens your mailbox read only, so nothing is marked as read, moved or deleted.

It never sends anything by itself. You tell it what to say, it writes a draft, and the draft is only sent when you press **Send** on it in Discord.

## Getting Started

### Prerequisites

* Software: `uv` (`brew install uv`). The script installs Python 3.11 and everything else into `.venv`.
* Setup: Run `../setup.sh email` first. It checks each login, saves the app passwords in the keychain, and saves the accounts and the check interval in `../config/`.
* Servers: The `llm` server on port `11434`.

### How to Enable / Access

1. Run `./start_mail.sh` in this folder, or run `../start.sh`, which starts it with the other servers once setup has been done.
2. Open http://127.0.0.1:8003/health. It should show `"ok": true`, your account count, and an empty `errors`.
3. Give it a few minutes, then open http://127.0.0.1:8003/mail.

## How to Use It

1. **From the app:** The Mail row on Home lists the emails with the model's notes, and shows any replies waiting for your approval. Tap an email to read the notes and write a reply, or use the pencil to write a new one. BellAI writes the draft and shows you the address and the text, and it is only sent when you press **Send**. A draft written in the app can be sent or discarded from Discord too, and the other way round, but only once.
2. **From Discord:** Use `/mail` in Discord to get the important and normal emails from the last check, newest first. Newsletters and promotions are left out.
3. **Write a reply:** Use `/reply` in Discord with the number shown next to the email in `/mail` and what to say, like `12` and `yes, Thursday works`. BellAI re-reads that email, writes the reply, and shows it with **Send** and **Discard** buttons. The reply goes to the sender's reply address, which is shown as **To** before you decide.
4. **Write a new email:** Use `/email` with an address and what to say, like `sam@example.com` and `ask if dinner Saturday is still on`. It is sent from the first account in `../config/email_accounts`.
5. **Send or discard:** Nothing leaves this Mac until someone on your Discord list presses **Send**. Each draft can be sent once, and no more than 10 emails go out per hour. Send fails if the account's SMTP login does. Send mail goes through port `587` with the same app password. `/drafts` shows the drafts still waiting.
6. **From the API:** `GET /mail?limit=20&importance=high` returns the notes, newest first. `importance` is optional and can be `high`, `normal` or `low`. The drafts are at `POST /drafts` (with `instruction` and either `to` or `reply_to`), `GET /drafts`, `POST /drafts/<id>/send` and `POST /drafts/<id>/discard`. The mail watcher only listens on this Mac. The app reaches the same endpoints through the [voice server](../voice/README.md) on port `8000`, which passes `/mail` and `/drafts` on (set `MAIL_URL` there if you change this port).
7. **What is checked:** The first check looks back 2 days, up to 25 emails per account. After that it picks up whatever is new since the last check. How often is set by `../setup.sh email`, and the default is 10 minutes.
8. **Change settings:** Run `../setup.sh email` again to add accounts or change the interval. Set `LLM_URL`, `MAIL_DB` (where the notes are saved, `mail.db` by default), `HOST` or `PORT` before `./start_mail.sh`. If you change the port, set `MAIL_URL` for the Discord bridge.
9. **Handle an error:** If `/health` shows an account under `errors`, the message says why. `no password in the keychain` means run `../setup.sh email` again, and a login error usually means the app password was revoked. If a send fails, the message says so, and that draft can't be sent again, so check your Sent folder before asking for a new one.

> ⚠️ **Warning:** An email can contain text written to trick an AI. The model is told to treat it as text to describe and never as instructions, and it can only write notes and drafts, so the worst case is a wrong summary or an odd draft that you then see before it goes. Read the **To** and the text of every draft before pressing Send, and don't rely on the summaries for anything where a mistake would cost you, like a payment deadline. Drafts are kept in `mail.db` until they are sent or discarded.
