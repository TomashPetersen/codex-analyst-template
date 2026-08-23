---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: none
---

# Review и promotion знания

```text
Прочитай AGENTS.md, PROJECT.md, knowledge/INDEX.md и candidate <CANDIDATE_REF>.
Проверь ownership, sources, confidence, review due, дубли, conflicts, privacy и
целевой канон. Покажи точный preview: какие строки и backlinks изменятся.

Ничего не применяй без отдельного явного approval и authority_ref. После approval
выполни восстановимый promotion, обнови graph и запусти knowledge, privacy и
structure gates. Не выполняй external write, commit или push.
```
