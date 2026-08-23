---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: none
---

# Создание Local Mastery

```text
Прочитай AGENTS.md, PROJECT.md, mastery/INDEX.md, mastery/INTENTS.json и
knowledge/INDEX.md. Проведи короткое интервью: какой повторяемый метод нужен,
какой у него вид (heuristic, checklist, workflow или standard), для каких intent
IDs, шаги, критерии применения, исключения, evidence и срок review.

Найди дубли. Создавай только один type: method candidate. Независимый evidence
должен показывать метод минимум в двух завершенных задачах, кроме прямой
коррекции владельца. Заполни MethodKind, MethodSummary и MethodAppliesTo при
вызове scripts/new-knowledge-candidate.ps1. Не меняй mastery/local и не создавай
Skill автоматически. Покажи candidate и остановись для approval. После отдельного
approval используй scripts/new-mastery.ps1 сначала с -WhatIf, затем без него.
```
