---
id: KC-YYYYMMDD-HHmmss-00000000
state: ready
type: fact | decision | constraint | preference | method
owner_scope: project
domain: idea | product | business | architecture | codebase | operations | research | mastery | instructions
method_kind: null
method_summary: null
method_applies_to: []
claim_key: unique-lowercase-key
target_ref: relative/path.md#section
source_refs:
  - relative/source.md
conflict_refs: []
confidence: high | medium | low | unknown
capture_basis: repo-derived | explicit-user-capture | research-derived | plan-closeout
data_class: public | internal
created_at: YYYY-MM-DDTHH:mm:ss+00:00
review_due: YYYY-MM-DD | null
authority_ref: policy:knowledge-contract-v1 | user-request:safe-stable-task-ref | docs/decisions/accepted-decision.md
applied_at: null
dismiss_reason: null
supersedes: null
---

# Краткий атомарный claim

## Основание

Кратко объясни, почему вывод пригодится в будущей работе. Ссылайся на `source_refs`, не копируй RAW, полный diff или сторонний текст.

## Предлагаемое изменение

Укажи точный минимальный текст для `target_ref`.

## Проверка дублей и противоречий

- Поиск по канону:
- Поиск по candidates:
- Противоречия:

`conflict_refs` содержит только нерешенные конфликты. Перед `applied` список должен быть пустым. `supersedes` обязан вести на существующий candidate, не на себя и не образовывать цикл.

## Обоснование lifecycle

Кратко объясни причину текущего state, authority, следующую проверку и, для dismissal, допустимый `dismiss_reason`. Machine state хранится только во frontmatter.

Promotion является проверяемым change set и считается завершенным только после target backlink, заполненных `applied_at` и `authority_ref`, пустых unresolved conflicts и зеленого strict gate.

Для `type: method` дополнительно обязательны `domain: mastery`, `method_kind: heuristic | checklist | workflow | standard`, короткий `method_summary`, непустой `method_applies_to` из [`mastery/INTENTS.json`](../../mastery/INTENTS.json), `claim_key: method.<id>`, `target_ref: mastery/local/INDEX.md#зарегистрированные-расширения`, `confidence: medium | high`, непустой `review_due` и learning evidence по [knowledge contract](../INDEX.md#обучаемые-методы). Для остальных типов method-поля остаются `null`, `null`, `[]`. Method candidate не изменяет Skill или Local Mastery автоматически.
