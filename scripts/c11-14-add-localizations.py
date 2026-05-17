#!/usr/bin/env python3
"""C11-14: append the new default-terminal-agent localization keys to
`Resources/Localizable.xcstrings`. Idempotent — re-running replaces existing
entries with our authored values.

Translations: English is the source-of-truth (set in source via
`String(localized:defaultValue:)`). The other six (ja, uk, ko, zh-Hans,
zh-Hant, ru) are the standard c11 set per CLAUDE.md."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Resources" / "Localizable.xcstrings"

# (key, en, ja, uk, ko, zh-Hans, zh-Hant, ru)
ENTRIES: list[tuple[str, str, str, str, str, str, str, str]] = [
    (
        "menu.pane.newBashTerminal",
        "New Bash Terminal",
        "新規 Bash ターミナル",
        "Новий Bash-термінал",
        "새 Bash 터미널",
        "新建 Bash 终端",
        "新增 Bash 終端機",
        "Новый Bash-терминал",
    ),
    (
        "settings.section.defaultTerminalAgent",
        "Default terminal agent",
        "デフォルトのターミナルエージェント",
        "Типовий агент термінала",
        "기본 터미널 에이전트",
        "默认终端代理",
        "預設終端代理",
        "Терминальный агент по умолчанию",
    ),
    (
        "settings.defaultTerminalAgent.note",
        "Applied to every new terminal surface (menu, keyboard, socket). Use “New Bash Terminal” to bypass for a single surface. Per-project overrides live in `.c11/agents.json`; per-workspace override is the metadata key `default_agent_use_bash` (set with `c11 set-metadata`). Distinct from the per-pane “A” launcher button below.",
        "すべての新規ターミナル面 (メニュー、キーボード、ソケット) に適用されます。1 つの面だけ回避するには「新規 Bash ターミナル」を使用してください。プロジェクト単位の上書きは `.c11/agents.json` に、ワークスペース単位の上書きはメタデータキー `default_agent_use_bash` (`c11 set-metadata` で設定) を使用します。下の「A」ペイン起動ボタンとは別物です。",
        "Застосовується до кожного нового термінала (меню, клавіатура, сокет). Використайте «Новий Bash-термінал», щоб обійти лише для одного. Перевизначення для проєкту — у `.c11/agents.json`; для робочої області — ключ метаданих `default_agent_use_bash` (встановлюйте через `c11 set-metadata`). Окремо від кнопки «A» нижче.",
        "모든 새 터미널 표면(메뉴, 키보드, 소켓)에 적용됩니다. 한 표면만 우회하려면 “새 Bash 터미널”을 사용하세요. 프로젝트별 재정의는 `.c11/agents.json`, 워크스페이스별 재정의는 메타데이터 키 `default_agent_use_bash` (`c11 set-metadata`로 설정)입니다. 아래의 패널별 “A” 런처 버튼과는 별개입니다.",
        "应用于每个新终端表面（菜单、键盘、套接字）。使用“新建 Bash 终端”可对单个表面绕过。项目级覆盖位于 `.c11/agents.json`；工作区级覆盖是元数据键 `default_agent_use_bash`（用 `c11 set-metadata` 设置）。与下方每窗格的“A”启动按钮不同。",
        "套用到每個新的終端機介面（選單、鍵盤、Socket）。使用「新增 Bash 終端機」可針對單一介面繞過。專案層級覆寫位於 `.c11/agents.json`；工作區層級覆寫是中繼資料鍵 `default_agent_use_bash`（用 `c11 set-metadata` 設定）。與下方每窗格的「A」啟動按鈕不同。",
        "Применяется к каждому новому терминалу (меню, клавиатура, сокет). Используйте «Новый Bash-терминал», чтобы обойти для одного. Переопределения уровня проекта — в `.c11/agents.json`; уровня рабочей области — ключ метаданных `default_agent_use_bash` (задаётся через `c11 set-metadata`). Отдельно от кнопки «A» под этим разделом.",
    ),
    (
        "settings.defaultAgent.type.label",
        "Agent type",
        "エージェントの種類",
        "Тип агента",
        "에이전트 유형",
        "代理类型",
        "代理類型",
        "Тип агента",
    ),
    (
        "settings.defaultAgent.type.bash",
        "Bash (no agent)",
        "Bash (エージェントなし)",
        "Bash (без агента)",
        "Bash (에이전트 없음)",
        "Bash（无代理）",
        "Bash（無代理）",
        "Bash (без агента)",
    ),
    (
        "settings.defaultAgent.type.claudeCode",
        "Claude Code",
        "Claude Code",
        "Claude Code",
        "Claude Code",
        "Claude Code",
        "Claude Code",
        "Claude Code",
    ),
    (
        "settings.defaultAgent.type.codex",
        "Codex",
        "Codex",
        "Codex",
        "Codex",
        "Codex",
        "Codex",
        "Codex",
    ),
    (
        "settings.defaultAgent.type.kimi",
        "Kimi",
        "Kimi",
        "Kimi",
        "Kimi",
        "Kimi",
        "Kimi",
        "Kimi",
    ),
    (
        "settings.defaultAgent.type.opencode",
        "OpenCode",
        "OpenCode",
        "OpenCode",
        "OpenCode",
        "OpenCode",
        "OpenCode",
        "OpenCode",
    ),
    (
        "settings.defaultAgent.type.custom",
        "Custom",
        "カスタム",
        "Користувацька",
        "사용자 지정",
        "自定义",
        "自訂",
        "Пользовательский",
    ),
    (
        "settings.defaultAgent.customCommand.label",
        "Custom command",
        "カスタムコマンド",
        "Користувацька команда",
        "사용자 지정 명령",
        "自定义命令",
        "自訂指令",
        "Пользовательская команда",
    ),
    (
        "settings.defaultAgent.customCommand.placeholder",
        "/usr/local/bin/myagent",
        "/usr/local/bin/myagent",
        "/usr/local/bin/myagent",
        "/usr/local/bin/myagent",
        "/usr/local/bin/myagent",
        "/usr/local/bin/myagent",
        "/usr/local/bin/myagent",
    ),
    (
        "settings.defaultAgent.model.label",
        "Model",
        "モデル",
        "Модель",
        "모델",
        "模型",
        "模型",
        "Модель",
    ),
    (
        "settings.defaultAgent.model.placeholder",
        "claude-opus-4-7",
        "claude-opus-4-7",
        "claude-opus-4-7",
        "claude-opus-4-7",
        "claude-opus-4-7",
        "claude-opus-4-7",
        "claude-opus-4-7",
    ),
    (
        "settings.defaultAgent.extraArgs.label",
        "Extra arguments",
        "追加の引数",
        "Додаткові аргументи",
        "추가 인자",
        "额外参数",
        "額外參數",
        "Дополнительные аргументы",
    ),
    (
        "settings.defaultAgent.extraArgs.placeholder",
        "--dangerously-skip-permissions",
        "--dangerously-skip-permissions",
        "--dangerously-skip-permissions",
        "--dangerously-skip-permissions",
        "--dangerously-skip-permissions",
        "--dangerously-skip-permissions",
        "--dangerously-skip-permissions",
    ),
    (
        "settings.defaultAgent.initialPrompt.label",
        "Initial prompt (optional)",
        "初期プロンプト (省略可)",
        "Початковий запит (необов’язково)",
        "초기 프롬프트 (선택)",
        "初始提示词（可选）",
        "初始提示（選填）",
        "Начальный запрос (необязательно)",
    ),
    (
        "settings.defaultAgent.cwd.label",
        "Working directory",
        "作業ディレクトリ",
        "Робочий каталог",
        "작업 디렉터리",
        "工作目录",
        "工作目錄",
        "Рабочий каталог",
    ),
    (
        "settings.defaultAgent.cwd.inherit",
        "Inherit from parent pane",
        "親ペインから継承",
        "Успадковано від батьківської панелі",
        "상위 패널에서 상속",
        "继承自父窗格",
        "由父窗格繼承",
        "Унаследовать от родительской панели",
    ),
    (
        "settings.defaultAgent.cwd.fixed",
        "Fixed path",
        "固定パス",
        "Фіксований шлях",
        "고정 경로",
        "固定路径",
        "固定路徑",
        "Фиксированный путь",
    ),
    (
        "settings.defaultAgent.fixedCwd.label",
        "Fixed path",
        "固定パス",
        "Фіксований шлях",
        "고정 경로",
        "固定路径",
        "固定路徑",
        "Фиксированный путь",
    ),
    (
        "settings.defaultAgent.fixedCwd.placeholder",
        "/Users/you/Projects",
        "/Users/you/Projects",
        "/Users/you/Projects",
        "/Users/you/Projects",
        "/Users/you/Projects",
        "/Users/you/Projects",
        "/Users/you/Projects",
    ),
    (
        "settings.defaultAgent.preview.label",
        "Command preview",
        "コマンドプレビュー",
        "Попередній перегляд команди",
        "명령 미리보기",
        "命令预览",
        "指令預覽",
        "Предпросмотр команды",
    ),
    (
        "settings.defaultAgent.preview.bash",
        "(bash — no startup command)",
        "(bash — 起動コマンドなし)",
        "(bash — без команди запуску)",
        "(bash — 시작 명령 없음)",
        "(bash — 无启动命令)",
        "(bash — 無啟動指令)",
        "(bash — без команды запуска)",
    ),
]

LANG_ORDER = ["en", "ja", "uk", "ko", "zh-Hans", "zh-Hant", "ru"]


def build_entry(values: tuple[str, ...]) -> dict:
    en, ja, uk, ko, zh_hans, zh_hant, ru = values
    return {
        "extractionState": "manual",
        "localizations": {
            lang: {"stringUnit": {"state": "translated", "value": v}}
            for lang, v in zip(LANG_ORDER, [en, ja, uk, ko, zh_hans, zh_hant, ru])
        },
    }


def main() -> int:
    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = data["strings"]
    added, updated = 0, 0
    for row in ENTRIES:
        key, *values = row
        entry = build_entry(tuple(values))
        if key in strings:
            updated += 1
        else:
            added += 1
        strings[key] = entry
    CATALOG.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"OK — added {added}, updated {updated} keys")
    return 0


if __name__ == "__main__":
    sys.exit(main())
