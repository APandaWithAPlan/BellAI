# bell discord bridge (mac): discord messages in, bell's replies out
# discord -> this bot -> llm (chat), food server (photos) or mail watcher (your inbox)
#
# only the user ids in DISCORD_ALLOWED_USERS (config/bellai.env) get an answer, in a dm or when the bot is @mentioned
#   text           chat reply from the llm, it remembers the last few messages in each channel
#   photo          meal analysis from the food server, answered as an embed (message text is a note for the photo)
# slash commands (the mail ones answer so only you see them):
#   /food 2 eggs   same, from a description and/or a photo
#   /mail          what matters in your inbox right now
#   /reply 12 yes, thursday works   a draft reply to email #12 from /mail
#   /email sam@example.com ask if dinner is on   a draft of a new email
#   /drafts        drafts still waiting for you
#   a draft shows up with Send and Discard buttons, nothing is sent until someone on the list presses Send
#   /reset         forget the conversation
#   /purge         delete the bot's recent messages in this channel, and forget the conversation
#
# the bot token comes from the keychain (bellai-discord), both are set up by ../setup.sh discord
# env: LLM_URL, FOOD_URL, MAIL_URL, BELL_SYSTEM_PROMPT
import logging
import os
import re
import subprocess
import sys
from collections import defaultdict, deque
from pathlib import Path

import discord
import httpx
from discord import app_commands

log = logging.getLogger("bell_discord")

HERE = Path(__file__).resolve().parent
CONFIG = HERE.parent / "config" / "bellai.env"
LLM_URL = os.environ.get("LLM_URL", "http://127.0.0.1:11434").rstrip("/")
FOOD_URL = os.environ.get("FOOD_URL", "http://127.0.0.1:8002").rstrip("/")
MAIL_URL = os.environ.get("MAIL_URL", "http://127.0.0.1:8003").rstrip("/")
HISTORY = 10  # messages remembered per channel
MAX_LEN = 2000  # discord refuses longer messages
PURGE_SCAN = 200  # newest messages /purge looks through for the bot's own
SYSTEM_PROMPT = os.environ.get("BELL_SYSTEM_PROMPT") or (
    "You are BellAI, a personal assistant chatting on Discord. Keep replies short and plain. "
    "If you don't know something, say so briefly. If a request is unclear, ask one short question."
)


class Problem(Exception):
    # something the person should be told about, anything else just says it failed
    pass


def load_allowed():
    settings = {}
    try:
        for line in CONFIG.read_text(encoding="utf-8").splitlines():
            key, _, value = line.partition("=")
            settings[key] = value
    except FileNotFoundError:
        sys.exit("no config/bellai.env, run ../setup.sh discord first")
    allowed = {int(i) for i in settings.get("DISCORD_ALLOWED_USERS", "").split() if i.isdigit()}
    if not allowed:
        sys.exit("no Discord user ids in config/bellai.env, run ../setup.sh discord first")
    return allowed


def load_token():
    r = subprocess.run(
        ["security", "find-generic-password", "-s", "bellai-discord", "-a", "bot", "-w"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        sys.exit("no bot token in the keychain, run ../setup.sh discord first")
    return r.stdout.strip()


def chunks(text):
    # break long replies at a line or a space
    while len(text) > MAX_LEN:
        cut = max(text.rfind("\n", 0, MAX_LEN), text.rfind(" ", 0, MAX_LEN))
        if cut <= 0:
            cut = MAX_LEN
        yield text[:cut]
        text = text[cut:].lstrip()
    if text:
        yield text


def food_embed(result):
    embed = discord.Embed(title="Meal", description=result["summary"], color=0x57A773)
    for item in result["items"][:10]:
        kcal = (item.get("nutrition") or {}).get("kcal")
        detail = f"{round(item['grams'])} g" + (f", {kcal} kcal" if kcal is not None else "")
        embed.add_field(name=item["label"][:200], value=detail)
    total = result["totals"]
    parts = [f"{total[key]} {unit}" for key, unit in
             (("kcal", "kcal"), ("protein_g", "g protein"), ("carbs_g", "g carbs"), ("fat_g", "g fat"))
             if total.get(key) is not None]
    if parts:
        embed.set_footer(text=" · ".join(parts))
    return embed


def draft_embed(draft, footer=None):
    embed = discord.Embed(title=draft["subject"][:250], description=draft["body"][:3500], color=0xE0A030)
    embed.add_field(name="To", value=draft["to"])
    embed.add_field(name="From", value=draft["account"])
    embed.set_footer(text=f"Draft #{draft['id']} · " + (footer or "nothing is sent until you press Send"))
    return embed


def reason(r):
    # the mail watcher explains its errors in plain words
    detail = r.json().get("detail") if r.headers.get("content-type", "").startswith("application/json") else None
    return detail if isinstance(detail, str) else "That didn't work."


def mail_embed(mail):
    embed = discord.Embed(title="Inbox", color=0x4A7BD0)
    if not mail:
        embed.description = "Nothing new that matters."
    for item in mail:
        lines = [item["sender"], item["summary"]]
        if item["action"]:
            lines.append(f"**To do:** {item['action']}" + (f" (due {item['due']})" if item["due"] else ""))
        embed.add_field(name=("❗ " if item["importance"] == "high" else "") + f"#{item['id']} " + item["subject"][:200],
                        value="\n".join(lines)[:1000], inline=False)
    return embed


# --- the bot

class Approve(discord.ui.View):
    def __init__(self, bell, draft_id):
        super().__init__(timeout=None)  # works until the bot restarts, then /drafts brings back the ones still waiting
        self.bell = bell
        self.draft_id = draft_id

    async def interaction_check(self, interaction):
        return interaction.user.id in self.bell.allowed

    @discord.ui.button(label="Send", style=discord.ButtonStyle.success)
    async def send(self, interaction, button):
        await self.decide(interaction, "send", "sent")

    @discord.ui.button(label="Discard", style=discord.ButtonStyle.secondary)
    async def discard(self, interaction, button):
        await self.decide(interaction, "discard", "discarded")

    async def decide(self, interaction, action, done):
        await interaction.response.defer()  # sending takes a moment
        try:
            r = await self.bell.http_client.post(f"{MAIL_URL}/drafts/{self.draft_id}/{action}", timeout=60)
        except httpx.TransportError:
            await interaction.followup.send("My mail watcher isn't running right now.", ephemeral=True)
            return
        if r.status_code == 200:
            embed = interaction.message.embeds[0]
            embed.set_footer(text=f"Draft #{self.draft_id} · {done}")
            await interaction.edit_original_response(embed=embed, view=None)
            self.stop()
            return
        await interaction.followup.send(reason(r), ephemeral=True)
        if r.status_code != 429:  # the draft is settled one way or another, only "too many" is worth pressing again
            await interaction.edit_original_response(view=None)
            self.stop()


class Tree(app_commands.CommandTree):
    async def interaction_check(self, interaction):
        # anyone in a shared server can see the commands, only the people on the list can use them
        if interaction.user.id not in self.client.allowed:
            raise app_commands.CheckFailure()
        return True

    async def on_error(self, interaction, error):
        error = getattr(error, "original", error)
        if isinstance(error, app_commands.CheckFailure):
            text = "You're not on my list."
        elif isinstance(error, Problem):
            text = str(error)
        else:
            log.error("command failed", exc_info=error)
            text = f"Sorry, that failed ({type(error).__name__})."
        if interaction.response.is_done():
            await interaction.followup.send(text)
        else:
            await interaction.response.send_message(text, ephemeral=True)


class Bell(discord.Client):
    def __init__(self, allowed):
        intents = discord.Intents.default()
        intents.message_content = True  # needs the Message Content Intent turned on for the bot
        super().__init__(intents=intents)
        self.allowed = allowed
        self.tree = Tree(self)
        self.history = defaultdict(lambda: deque(maxlen=HISTORY))
        self.http_client = None

    async def setup_hook(self):
        self.http_client = httpx.AsyncClient(timeout=httpx.Timeout(120, connect=5))
        add_commands(self)
        await self.tree.sync()  # global, so they work in a dm too

    async def close(self):
        if self.http_client:
            await self.http_client.aclose()
        await super().close()

    async def on_ready(self):
        log.info("bell discord ready as %s", self.user)

    async def chat(self, channel, text):
        messages = [*self.history[channel], {"role": "user", "content": text}]
        body = {"model": "default_model", "messages": [{"role": "system", "content": SYSTEM_PROMPT}, *messages]}
        try:
            r = await self.http_client.post(f"{LLM_URL}/v1/chat/completions", json=body)
        except httpx.TransportError:
            raise Problem("My chat model isn't running right now.")
        if r.status_code != 200:
            raise RuntimeError(f"llm {r.status_code}: {r.text[:300]}")
        reply = r.json()["choices"][0]["message"]["content"].strip()
        self.history[channel].extend([messages[-1], {"role": "assistant", "content": reply}])
        return reply

    async def analyze(self, image, note):
        files = {"image": (image.filename, await image.read(), image.content_type)} if image else None
        try:
            r = await self.http_client.post(f"{FOOD_URL}/analyze", files=files, data={"text": note})
        except httpx.TransportError:
            raise Problem("My food model isn't running right now.")
        if r.status_code in (400, 413, 503):  # these come with a reason meant for people
            raise Problem(r.json().get("detail", "That didn't work."))
        if r.status_code != 200:
            raise RuntimeError(f"food {r.status_code}: {r.text[:300]}")
        return food_embed(r.json())

    async def inbox(self):
        try:
            r = await self.http_client.get(f"{MAIL_URL}/mail", params={"limit": 25})
        except httpx.TransportError:
            raise Problem("My mail watcher isn't running right now.")
        if r.status_code != 200:
            raise RuntimeError(f"mail {r.status_code}: {r.text[:300]}")
        return mail_embed([m for m in r.json()["mail"] if m["importance"] != "low"][:10])  # newsletters stay out

    async def make_draft(self, instruction, **who):
        try:
            r = await self.http_client.post(f"{MAIL_URL}/drafts", json={"instruction": instruction, **who})
        except httpx.TransportError:
            raise Problem("My mail watcher isn't running right now.")
        if r.status_code in (400, 404, 409, 422, 502):
            raise Problem(reason(r))
        if r.status_code != 200:
            raise RuntimeError(f"mail {r.status_code}: {r.text[:300]}")
        return r.json()

    async def waiting_drafts(self):
        try:
            r = await self.http_client.get(f"{MAIL_URL}/drafts", params={"limit": 5})
        except httpx.TransportError:
            raise Problem("My mail watcher isn't running right now.")
        if r.status_code != 200:
            raise RuntimeError(f"mail {r.status_code}: {r.text[:300]}")
        return r.json()["drafts"]

    async def show_draft(self, interaction, draft):
        await interaction.followup.send(embed=draft_embed(draft), view=Approve(self, draft["id"]))

    async def on_message(self, message):
        if message.author.bot or message.author.id not in self.allowed:
            return
        if message.guild is not None and self.user not in message.mentions:
            return  # in a server it only answers when asked
        text = message.content
        for mention in (f"<@{self.user.id}>", f"<@!{self.user.id}>"):
            text = text.replace(mention, "")
        text = text.strip()
        images = [a for a in message.attachments if (a.content_type or "").startswith("image/")]
        if not text and not images:
            return

        try:
            async with message.channel.typing():
                if images:
                    await message.reply(embed=await self.analyze(images[0], text), mention_author=False)
                else:
                    for part in chunks(await self.chat(message.channel.id, text)):
                        await message.reply(part, mention_author=False)
        except Problem as e:
            await message.reply(str(e), mention_author=False)
        except Exception as e:
            log.exception("message failed")
            await message.reply(f"Sorry, that failed ({type(e).__name__}).", mention_author=False)


def add_commands(bell):
    tree = bell.tree
    private = dict(ephemeral=True, thinking=True)  # mail stays between you and the bot, even in a server

    @tree.command(description="What matters in your inbox right now")
    async def mail(interaction: discord.Interaction):
        await interaction.response.defer(**private)
        await interaction.followup.send(embed=await bell.inbox())

    @tree.command(description="Draft a reply to an email from /mail")
    @app_commands.describe(number="The number shown next to the email in /mail", message="What to say")
    async def reply(interaction: discord.Interaction, number: int, message: str):
        await interaction.response.defer(**private)
        await bell.show_draft(interaction, await bell.make_draft(message, reply_to=number))

    @tree.command(description="Draft a new email")
    @app_commands.describe(to="Who to send it to", message="What to say")
    async def email(interaction: discord.Interaction, to: str, message: str):
        if not re.fullmatch(r"\S+@\S+", to):
            raise Problem("That doesn't look like an email address.")
        await interaction.response.defer(**private)
        await bell.show_draft(interaction, await bell.make_draft(message, to=to))

    @tree.command(description="Drafts still waiting for you to send or discard")
    async def drafts(interaction: discord.Interaction):
        await interaction.response.defer(**private)
        waiting = await bell.waiting_drafts()
        if not waiting:
            await interaction.followup.send("No drafts waiting.")
        for draft in reversed(waiting):
            await bell.show_draft(interaction, draft)

    @tree.command(description="Work out the nutrition in a meal")
    @app_commands.describe(what="What you ate, like 2 eggs and toast", photo="Or a photo of it")
    async def food(interaction: discord.Interaction, what: str = "", photo: discord.Attachment | None = None):
        if photo and not (photo.content_type or "").startswith("image/"):
            raise Problem("That file isn't a photo.")
        if not photo and not what.strip():
            raise Problem("Tell me what you ate, like `/food 2 eggs and toast`, or attach a photo.")
        await interaction.response.defer(thinking=True)
        await interaction.followup.send(embed=await bell.analyze(photo, what.strip()))

    @tree.command(description="Forget the conversation in this channel")
    async def reset(interaction: discord.Interaction):
        bell.history.pop(interaction.channel_id, None)
        await interaction.response.send_message("Okay, starting fresh.")

    @tree.command(description="Delete the bot's recent messages in this channel and forget the conversation")
    async def purge(interaction: discord.Interaction):
        if interaction.channel is None:
            raise Problem("I can't see this channel.")
        await interaction.response.defer(ephemeral=True, thinking=True)
        bell.history.pop(interaction.channel_id, None)
        deleted = 0
        try:
            async for message in interaction.channel.history(limit=PURGE_SCAN):
                if message.author.id == bell.user.id:
                    await message.delete()
                    deleted += 1
        except discord.Forbidden:
            raise Problem("I'm not allowed to read this channel's history.")
        await interaction.followup.send(f"Deleted {deleted} of my messages and forgot the conversation.")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    log.info("llm %s | food %s", LLM_URL, FOOD_URL)
    Bell(load_allowed()).run(load_token(), log_handler=None)
