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

> ✅ **Claude task done · my-project (21:00)**
> Created notify-complete.ps1 and wired up the Stop hook. Notifications now pop when work finishes…

> 🔔 **Claude needs input · my-project (21:05)**
> Claude needs your permission to use Bash

- ✅ **Done** — hooks into the **`Stop`** event, reads the transcript, and shows Claude's **last message** as a summary.
- 🔔 **Needs you** — hooks into the **`Notification`** event, so you're pinged when Claude is waiting for input or a permission choice (no more staring at an idle terminal).
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

**Turn it on/off** anytime from the `/plugin` menu.

---

## 🔧 Tweak & troubleshoot

| Want to... | Do this |
|---|---|
| 🔕 See it less often | `Stop` fires every turn, so even short chats ding. Add a condition in `scripts/notify-complete.ps1`. |
| 🐛 Debug | Check the log at `~/.claude/notify-complete.log`. |
| 🙈 No toast appears | Check **Windows → Notifications** are on, and **Focus assist / Do Not Disturb** is off. |

---

## 🗂️ Project layout

```text
ClaudeDing/
├─ .claude-plugin/marketplace.json     # marketplace: claudeding
├─ claudeding/                          # the plugin
│  ├─ .claude-plugin/plugin.json
│  ├─ hooks/hooks.json                  # Stop + Notification hooks → run the script
│  └─ scripts/notify-complete.ps1       # the notifier (UTF-8 with BOM)
├─ README.md                            # you are here 🇺🇸
└─ README.ko.md                         # 🇰🇷
```

> ⚠️ Note: the `.ps1` is saved as **UTF-8 with BOM** on purpose — Windows PowerShell 5.1
> misreads BOM-less UTF-8 and mangles non-ASCII characters.

---

<p align="center"><sub>Made with 🩵 for forgetful multitaskers.</sub></p>
