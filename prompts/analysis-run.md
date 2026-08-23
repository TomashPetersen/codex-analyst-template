---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: none
---

# Один ограниченный аналитический запуск

```text
Задача: <ЗАДАЧА>. Task ref: <TASK_REF>. Intent: <INTENT_ID>.

Используй it-analysis. Прочитай AGENTS.md, PROJECT.md, INDEX.md,
analysis/CONTRACT.md и релевантные domain indexes. Уточни решение, bounded
questions, scope, источники, stop conditions и authority. Один такой run не
создает implementation plan.

Создай run только через scripts/new-analysis-run.ps1: ровно восемь файлов.
Передай до трех независимых bounded questions подходящим read-only project
agents. Lead Analyst остается единственным writer и выполняет synthesis. Затем
отдельно запусти analysis_reviewer и analysis_red_team. Если multi-agent
недоступен, выполни те же роли последовательно и явно зафиксируй fallback.

Run является working evidence. Не меняй канон, candidate lifecycle, Git index,
commit, push или внешние системы без отдельного разрешенного маршрута.
```
