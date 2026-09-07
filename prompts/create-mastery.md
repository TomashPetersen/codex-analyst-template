---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: none
---

# Предложение локального метода работы

```text
Прочитай AGENTS.md, PROJECT.md, mastery/INDEX.md, mastery/INTENTS.json и
knowledge/INDEX.md. Проведи короткое интервью: какой повторяемый метод нужен
и к какому виду он относится - практическое правило (heuristic), список проверки
(checklist), порядок работы (workflow) или стандарт (standard). Уточни типы задач
по идентификаторам intent, шаги, условия применения, исключения, подтверждающий
опыт и срок повторной проверки.

Найди дубли. Создай только одно предложение для базы знаний с type: method.
Независимые подтверждения должны показывать применение метода минимум в двух
завершенных задачах; исключение - прямая поправка владельца. Заполни MethodKind,
MethodSummary и MethodAppliesTo при вызове scripts/new-knowledge-candidate.ps1.
Не меняй mastery/local и не создавай навык Codex автоматически.
Покажи предложение и дождись одобрения. После отдельного одобрения используй
scripts/new-mastery.ps1 сначала с -WhatIf, затем без него.
```
