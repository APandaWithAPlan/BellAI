# Running the AI GUI-testing experiment yourself

This file is how to reproduce the experiment with no help.

**What it does:** seeds five known bugs into a *copy* of the iOS app, lets AI agents explore it through the simulator, and scores what each agent reports against an answer key ([`seeded/bugs.json`](seeded/bugs.json)).

| Part | File |
| --- | --- |
| The tester: Qwen reads a screenshot and the accessibility tree | `qwen_agent.py` |
| Runs the small (4b) and the big (27b) Qwen | `run_qwen.sh` |
| Seeded bugs (applied to a copy) | `seeded/seed.py`, `seeded/seeded-bugs.patch` |
| Answer key and scorer | `seeded/bugs.json`, `seeded/score.py` |
| Prompt for the Claude comparison run | `seeded/claude_prompt.md` |
| Screenshot-only tester from run 2, not maintained | `old/qwen_agent_vision_only.py` |

## 0. What you need
- A Mac with Xcode and an iOS simulator runtime, Python 3, [Homebrew](https://brew.sh), and [uv](https://docs.astral.sh/uv/) (`brew install uv`).
- A **vision-capable** model behind an Ollama-style `/api/chat` endpoint. I used `qwen3.5:4b-q4_K_M` through the NVIDIA PAIR proxy at `http://127.0.0.1:11435`. Any other endpoint works with `--endpoint` and `--model`; check that the model lists `vision` in its capabilities (`curl <endpoint>/api/show -d '{"model":"<name>"}'`).
- The BellAI macserver (for the chat and data servers the app talks to). Voice is deliberately left off.

All commands below run from the repo root.

## 1. Pick and prepare the simulator
```bash
xcrun simctl list devices available | grep -i iphone
```
```bash
export UDID=<pick an iPhone id from that list>
```
```bash
xcrun simctl boot $UDID
```
**Dark mode matters.** Bug N1 (faint hint text on the BellAI tab) only appears in dark mode:
```bash
xcrun simctl ui $UDID appearance dark
```
The screenshots and tap coordinates assume a 402×874-point screen (iPhone 17 / 18 Pro class). A different size needs `W, H` changed at the top of both agent scripts.

## 2. Install idb (the agents' "hands": tap, swipe, accessibility tree)
```bash
brew tap facebook/fb && brew trust --formula facebook/fb/idb-companion && brew install idb-companion
```
```bash
uv venv --python 3.11 ~/.idbenv && uv pip install --python ~/.idbenv/bin/python fb-idb
```
```bash
export IDB=~/.idbenv/bin/idb
```
Start the companion for your simulator, in its own terminal tab, and leave it running:
```bash
idb_companion --udid $UDID --grpc-port 10880
```
```bash
$IDB connect localhost 10880
```
Check: `$IDB ui describe-all --udid $UDID | head -c 300` should print JSON.

## 3. Start the test servers on spare ports
The app is pointed at ports 11444 (chat) and 8011 (tasks) so it never touches your normal servers on 11434 and 8001. Run each in its own tab:
```bash
PORT=11444 BACKEND_PORT=11445 macserver/llm/start_llm.sh
```
```bash
cp macserver/data/bellai.db /tmp/bellai-test.db && DATA_DB=/tmp/bellai-test.db PORT=8011 macserver/data/start_data.sh
```
(`BACKEND_PORT` is the small override added to `macserver/llm/ollama_compat.py`; the default stays 11435.) Check: `curl http://127.0.0.1:11444/api/version`.
The data server uses a **copy** of the database, so agent runs can't change your real tasks.

## 4. Build and install the seeded copy
The seeds go into a copy, never into your source tree. Apply them to a fresh copy only once.
```bash
rm -rf /tmp/seeded && mkdir -p /tmp/seeded && cp -R iOS-App /tmp/seeded/iOS-App && python3 docs/ai-gui-testing/seeded/seed.py /tmp/seeded/iOS-App
```
```bash
xcodebuild -project /tmp/seeded/iOS-App/BellAI.xcodeproj -scheme BellAI -configuration Debug -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath /tmp/seeded/dd -skipMacroValidation -quiet build
```
```bash
xcrun simctl install $UDID /tmp/seeded/dd/Build/Products/Debug-iphonesimulator/BellAI.app
```
The bundle id is read from the app: `export BID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" /tmp/seeded/dd/Build/Products/Debug-iphonesimulator/BellAI.app/Info.plist)`.
To see the original app again, rebuild `iOS-App` itself and install that.

## 5. Run the testers
```bash
docs/ai-gui-testing/run_qwen.sh
```
This runs the small (`qwen3.5:4b-q4_K_M`) and then the big (`qwen3.8:27b-q4_K_M`) tester, 3 runs each, putting the app back in the same state before every run. Pick one with `run_qwen.sh small` or `run_qwen.sh big`, and set the number of runs with a second argument, `run_qwen.sh big 1`. The first call to a model can take close to a minute while it loads, and the big one is slower per step (about 5 s against 1 s).
Logs and screenshots go to `docs/ai-gui-testing/seeded/runs/<small|big>/<n>/`, overwriting what is there; copy the folder first if you want to keep it.
It needs `UDID` exported (see step 1) or a single booted simulator. Optional env vars: `IDB`, `BID`, `ENDPOINT`, `STEPS`.
To run one tester by hand: `python3 docs/ai-gui-testing/qwen_agent.py <model> <folder>`.
The big model must be asked for by its full name. Plain `qwen3.8:27b` can answer "no available node advertises the requested model" even when `qwen3.8:27b-q4_K_M` works.

## 6. Score
```bash
python3 docs/ai-gui-testing/seeded/score.py docs/ai-gui-testing/seeded/bugs.json docs/ai-gui-testing/seeded/runs/small/* docs/ai-gui-testing/seeded/runs/big/*
```
Pass any run folders; they are grouped by the folder they are in (`small`, `big`). The scorer matches each reported bug against the regex patterns in `bugs.json` and also lists the reports that matched nothing, which you should read by hand: the app has real bugs that are not in the key.

## 7. The Claude comparison run (needs Claude)
The agent that scores must not know the answers, so use a fresh session:
1. Reset the app first: the `defaults write` and `simctl launch` lines inside `run_qwen.sh`.
2. Open a **new** Claude Code session with the simulator tool, paste [`seeded/claude_prompt.md`](seeded/claude_prompt.md), and fill in the two placeholders (UDID and log path).
3. Score `.../runs/claude/rep1` with the command above.
Don't tell the session what the seeds are or point it at this folder.

## Gotchas learned the hard way
- **The Reset button** on the Settings screen wipes the saved server settings. That is why `run_qwen.sh` rewrites them before every run; running agents by hand, restore them yourself (the four `defaults write` lines) or later runs will have no backend.
- **Port clashes:** NVIDIA PAIR claims 11434 and 11435 on the same Mac. The test ports 11444, 11445 and 8011 avoid that.
- **Environment artifacts** (voice server off, mail server offline, location unavailable in the simulator) are counted separately by the scorer. Agents cannot tell them from app bugs.
- **Don't trust a "bug" without checking it.** Several early suspicions (all "connected", an endless spinner) were environment effects, found by looking at the process list and the source.
- Agents can change app data inside the simulator (for example pressing Save on Preferences). The scripts' skip list covers send, reset, delete and similar labels only.
