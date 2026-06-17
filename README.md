<!-- LANGUAGE SWITCH -->
<p align="right">
  <a href="README.md">🇺🇸 English</a> ·
  <a href="README.ko.md">🇰🇷 한국어</a>
</p>

<h1 align="center">🔔 ClaudeDing</h1>

<p align="center">
  <i>Ding! Your Claude is done. 🐣</i><br/>
  A tiny Claude Code plugin that pops a friendly <b>Windows toast</b><br/>
  when your CLI <b>finishes a task</b> — or when it <b>needs your input</b>.
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6?logo=windows">
  <img alt="claude code" src="https://img.shields.io/badge/Claude%20Code-plugin-8A63D2">
  <img alt="deps" src="https://img.shields.io/badge/dependencies-none-brightgreen">
</p>

---

## 🐣 What is this?

You kick off a long task in Claude Code, switch to another window... and forget about it.

**ClaudeDing** taps you on the shoulder. Two kinds of dings:

> ✅ **Task done · my-project (21:00)**
> Created notify-complete.ps1 and wired up the Stop hook.

> 🔔 **Waiting · my-project (21:05)**
> Waiting for permission to use Bash.

- ✅ **Done** — hooks into the **`Stop`** event, reads the transcript, and shows Claude's last message as **one clean line** (URLs, checklists, and markdown stripped out).
- 🔔 **Needs you** — hooks into the **`Notification`** event, so you're pinged when Claude is waiting for input or a permission choice. English messages are rewritten in natural language so you can see *what* (e.g. which tool) it's waiting on.
- 👆 **Click to return** — clicking a toast brings the **terminal window** Claude was running in back to the foreground.
- ⏰ **Reminders** — leave a **permission prompt** (Claude blocked mid-task) unanswered and it re-pings on a configurable interval (default **1 min**) until you respond. The **idle "waiting for input"** toast after everything is done rings just once.
- 🍃 **Zero dependencies** — uses Windows' built-in toast API. No modules to install.

---

## 📦 Install

Run these two lines inside Claude Code:

```text
/plugin marketplace add applan/ClaudeDing
/plugin install claudeding@claudeding
```

That's it! 🎉 Notifications start from your next session.
(If nothing fires yet, open `/hooks` once to reload config, or restart Claude Code.)

> 💡 Prefer a local checkout? Point the marketplace at the folder instead:
> ```text
> /plugin marketplace add C:\path\to\ClaudeDing
> ```

---

## ▶️ How it runs

Nothing to launch — it works automatically. 🛋️

- **When a task finishes** → the **`Stop`** hook fires → `notify-complete.ps1` reads the transcript, builds a one-line summary, and shows a ✅ toast.
- **When Claude needs you** → the **`Notification`** hook fires → the same script shows a 🔔 toast with what it's waiting for (e.g. a permission prompt).

- **If you don't respond** → the **`Notification`** toast re-fires on your configured interval. It stops automatically once you submit input (`UserPromptSubmit`) or work resumes.
- **When you click a toast** → the `claudeding://` protocol finds that session's terminal window and **focuses** it.

**Turn it on/off** anytime from the `/plugin` menu.

---

## ⏰ Reminders

Leave a **permission prompt** (Claude blocked mid-task) unanswered and it re-pings on an interval. The idle **"waiting for input"** toast after all tasks finish rings only once. Tune it in `~/.claude/claudeding.config.json` (defaults apply if the file is absent):

```json
{
  "remindInterval": "1m",
  "remindMax": 10
}
```

- **`remindInterval`** — how often to re-ping. Use `30s`, `1m`, `2h`; a bare number means minutes. Set `"off"` or `"0"` to disable. Default `1m` (min 5s to avoid spam).
- **`remindMax`** — max reminders per wait. `0` means unlimited. Default `10`.

> Reminders stop the moment you respond, so you usually get one or two and that's it.

---

## 🔧 Tweak & troubleshoot

| Want to... | Do this |
|---|---|
| 🔕 See it less often | `Stop` fires every turn, so even short chats ding. Add a condition in `scripts/notify-complete.ps1`. |
| ⏰ Turn off reminders | Set `remindInterval` to `"off"` in `~/.claude/claudeding.config.json`. |
| 🐛 Debug | Check the log at `~/.claude/notify-complete.log`. |
| 🐢 Toasts sometimes lag | Check `~/.claude/notify-perf.log`. A large `startup` value means PowerShell cold-start; small `startup` but still late points to **Focus assist**. |
| 🖱️ Click doesn't focus | Windows Terminal only restores at the **window** level (a specific tab can't be picked). If the window was closed, there's nothing to return to. |
| 🙈 No toast appears | Check **Windows → Notifications** are on, and **Focus assist / Do Not Disturb** is off. |

---

## 🗂️ Project layout

```text
ClaudeDing/
├─ .claude-plugin/marketplace.json     # marketplace: claudeding
├─ claudeding/                          # the plugin
│  ├─ .claude-plugin/plugin.json
│  ├─ hooks/hooks.json                  # Stop · Notification · UserPromptSubmit hooks
│  └─ scripts/                          # all UTF-8 with BOM
│     ├─ notify-complete.ps1            #   hook entry (toast + start/clear reminders)
│     ├─ _common.ps1                    #   shared: toast, config, copy, window-find, locks
│     ├─ remind-loop.ps1               #   background reminder loop
│     ├─ focus.ps1                      #   click handler — focuses the terminal window
│     └─ focus.vbs                      #   windowless launcher for focus.ps1 (no console flash)
├─ README.md                            # you are here 🇺🇸
└─ README.ko.md                         # 🇰🇷
```

> ⚠️ Note: the `.ps1` is saved as **UTF-8 with BOM** on purpose — Windows PowerShell 5.1
> misreads BOM-less UTF-8 and mangles non-ASCII characters.

---

<p align="center"><sub>Made with 🩵 for forgetful multitaskers.</sub></p>
