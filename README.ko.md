<!-- LANGUAGE SWITCH -->
<p align="right">
  <a href="README.md">🇺🇸 English</a> ·
  <a href="README.ko.md">🇰🇷 한국어</a>
</p>

<h1 align="center">🔔 ClaudeDing</h1>

<p align="center">
  <i>딩! Claude 작업 끝났어요. 🐣</i><br/>
  Claude CLI가 <b>작업을 끝냈을 때</b> — 또는 <b>당신의 입력이 필요할 때</b><br/>
  <b>Windows 토스트 알림</b>으로 알려주는 작은 Claude Code 플러그인입니다.
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6?logo=windows">
  <img alt="claude code" src="https://img.shields.io/badge/Claude%20Code-plugin-8A63D2">
  <img alt="deps" src="https://img.shields.io/badge/dependencies-none-brightgreen">
</p>

---

## 🐣 이게 뭐예요?

긴 작업을 Claude Code에 시켜놓고 다른 창으로 넘어갔다가… 깜빡하셨죠?

**ClaudeDing**이 어깨를 톡톡 두드려 줍니다. 두 가지 알림이 있어요:

> ✅ **작업 완료 · my-project (21:00)**
> notify-complete.ps1 스크립트를 만들고 Stop hook을 연결했습니다.

> 🔔 **입력 대기 · my-project (21:05)**
> Bash 사용을 허용할지 기다리고 있어요.

- ✅ **완료** — **`Stop`** 이벤트에 연결되어, 트랜스크립트에서 Claude의 **마지막 메시지**를 **핵심 한 줄**로 요약해 보여줍니다 (URL·체크리스트·마크다운은 걷어냄).
- 🔔 **입력 필요** — **`Notification`** 이벤트에 연결되어, Claude가 입력이나 권한 선택을 기다릴 때 알려줍니다. 영어 메시지를 **자연스러운 한국어**로 바꿔 무엇을(예: 어떤 도구) 기다리는지 한눈에 보입니다.
- 👆 **클릭하면 복귀** — 알림을 누르면 Claude가 돌던 **터미널 창이 최상단으로** 돌아옵니다.
- ⏰ **리마인드** — 입력/선택을 안 한 채 두면 설정 주기(기본 **1분**)마다 다시 알려줍니다. 응답하면 자동으로 멈춰요.
- 🍃 **의존성 0** — Windows 내장 토스트 API만 사용해서 설치할 모듈이 없어요.

---

## 📦 설치

Claude Code 안에서 아래 두 줄을 실행하세요:

```text
/plugin marketplace add applan/ClaudeDing
/plugin install claudeding@claudeding
```

끝이에요! 🎉 다음 세션부터 알림이 뜹니다.
(아직 안 뜨면 `/hooks`를 한 번 열어 설정을 다시 읽히거나 Claude Code를 재시작하세요.)

> 💡 로컬 폴더로 쓰고 싶다면 마켓플레이스를 폴더로 지정하세요:
> ```text
> /plugin marketplace add C:\path\to\ClaudeDing
> ```

---

## ▶️ 어떻게 실행되나요?

따로 켤 필요 없어요 — 자동으로 동작합니다. 🛋️

- **작업이 끝나면** → **`Stop`** hook 발생 → `notify-complete.ps1`이 트랜스크립트를 읽어 한 줄 요약으로 ✅ 토스트를 띄웁니다.
- **Claude가 입력을 기다리면** → **`Notification`** hook 발생 → 같은 스크립트가 무엇을 기다리는지(예: 권한 요청) 🔔 토스트로 알려줍니다.

- **응답을 안 하고 두면** → 설정 주기마다 **`Notification`** 토스트를 다시 띄웁니다. 입력을 제출하거나(`UserPromptSubmit`) 작업이 진행되면 자동으로 멈춥니다.
- **알림을 클릭하면** → `claudeding://` 프로토콜이 그 세션의 터미널 창을 찾아 **포커스**합니다.

켜고 끄는 건 언제든 `/plugin` 메뉴에서 가능합니다.

---

## ⏰ 리마인드 설정

입력/선택 대기 알림을 응답 없이 두면 일정 주기로 다시 알려줍니다. `~/.claude/claudeding.config.json`에서 조정하세요(없으면 기본값으로 동작):

```json
{
  "remindInterval": "1m",
  "remindMax": 10
}
```

- **`remindInterval`** — 리마인드 주기. `30s`(초) · `1m`(분) · `2h`(시간) 형식. 단위 없는 숫자는 분. **끄려면** `"off"` 또는 `"0"`. 기본 `1m`. (스팸 방지를 위해 최소 5초)
- **`remindMax`** — 최대 리마인드 횟수. `0`이면 무제한. 기본 `10`.

> 응답하면 자동으로 멈추므로 보통 한두 번 울리고 끝납니다.

---

## 🔧 조정 & 문제 해결

| 이럴 땐 | 이렇게 |
|---|---|
| 🔕 너무 자주 떠요 | `Stop`은 매 턴마다 발생해서 짧은 대화에도 떠요. `scripts/notify-complete.ps1`에 조건을 추가하세요. |
| ⏰ 리마인드를 끄고 싶어요 | `~/.claude/claudeding.config.json`의 `remindInterval`을 `"off"`로. |
| 🐛 디버그 | 로그 확인: `~/.claude/notify-complete.log` |
| 🐢 가끔 알림이 늦어요 | 지연 구간 로그(`~/.claude/notify-perf.log`)의 `startup` 값을 보세요. 값이 크면 PowerShell 콜드 스타트, 작은데도 늦으면 **집중 지원**을 의심하세요. |
| 🙈 알림이 안 보여요 | **Windows → 알림**이 켜져 있는지, **집중 지원/방해 금지**가 꺼져 있는지 확인하세요. |
| 🖱️ 클릭해도 창이 안 떠요 | Windows Terminal은 **창 단위**로만 복귀돼요(특정 탭은 못 고름). 창이 닫혔으면 복귀 대상이 없습니다. |

---

## 🗂️ 프로젝트 구조

```text
ClaudeDing/
├─ .claude-plugin/marketplace.json     # 마켓플레이스: claudeding
├─ claudeding/                          # 플러그인 본체
│  ├─ .claude-plugin/plugin.json
│  ├─ hooks/hooks.json                  # Stop · Notification · UserPromptSubmit hook
│  └─ scripts/                          # 모두 UTF-8 BOM
│     ├─ notify-complete.ps1            #   hook 진입점 (토스트 + 리마인드 시작/해제)
│     ├─ _common.ps1                    #   공용: 토스트·설정·문구·창 탐색·잠금
│     ├─ remind-loop.ps1               #   백그라운드 리마인드 루프
│     ├─ focus.ps1                      #   클릭 시 터미널 창 복귀(프로토콜 핸들러)
│     └─ focus.vbs                      #   focus.ps1 을 창 없이 실행(콘솔 깜빡임 방지)
├─ README.md                            # 🇺🇸
└─ README.ko.md                         # 지금 여기 🇰🇷
```

> ⚠️ 참고: `.ps1`은 일부러 **UTF-8 BOM**으로 저장했어요 — Windows PowerShell 5.1이
> BOM 없는 UTF-8을 잘못 읽어 한글/특수문자를 깨뜨리기 때문입니다.

---

<p align="center"><sub>깜빡 잘하는 멀티태스커들을 위해 🩵 으로 만들었습니다.</sub></p>
