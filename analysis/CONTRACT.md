# Контракт аналитических артефактов

## Working и canon

`analysis/runs/**` хранит рабочую декомпозицию, источники, предложения, review и решение о handoff. Run не владеет нормативными требованиями. Canon хранится только в `business/analysis/**` и `docs/analysis/**`, а один ID имеет ровно один owner file.

## Закрытый namespace

| Prefix | `artifact_kind` | Exact ID | Единственный owner path |
|---|---|---|---|
| `STK` | `stakeholder` | `^STK-[0-9]{4}$` | `business/analysis/stakeholders/` |
| `CAP` | `capability` | `^CAP-[0-9]{4}$` | `business/analysis/capabilities/` |
| `BP` | `business-process` | `^BP-[0-9]{4}$` | `business/analysis/processes/` |
| `RULE` | `business-rule` | `^RULE-[0-9]{4}$` | `business/analysis/rules/` |
| `BR` | `business-requirement` | `^BR-[0-9]{4}$` | `business/analysis/requirements/` |
| `UC` | `use-case` | `^UC-[0-9]{4}$` | `docs/analysis/requirements/` |
| `FR` | `functional-requirement` | `^FR-[0-9]{4}$` | `docs/analysis/requirements/` |
| `NFR` | `nonfunctional-requirement` | `^NFR-[0-9]{4}$` | `docs/analysis/requirements/` |
| `DATA` | `data-model` | `^DATA-[0-9]{4}$` | `docs/analysis/models/` |
| `INT` | `integration-contract` | `^INT-[0-9]{4}$` | `docs/analysis/models/` |
| `SYS` | `system-model` | `^SYS-[0-9]{4}$` | `docs/analysis/models/` |
| `AC` | `acceptance-criterion` | `^AC-[0-9]{4}$` | `docs/analysis/requirements/` |
| `SPEC` | `specification` | `^SPEC-[0-9]{4}$` | `docs/analysis/specifications/` |
| `CR` | `change-request` | `^CR-[0-9]{4}$` | `docs/analysis/changes/` |
| `REV` | `review-decision` | `^REV-[0-9]{4}$` | `docs/analysis/reviews/` |

ID глобально уникален без учета регистра. Frontmatter хранит exact uppercase ID. Filename имеет форму `<id-lowercase>-<slug>.md`. Синонимичные prefixes и artifact kinds запрещены.

## Canonical schema

Каждый canonical analytical artifact, кроме `INDEX.md`, `README.md` и `TEMPLATE.md`, имеет только эти поля:

```yaml
---
artifact_kind: functional-requirement
id: FR-0001
status: draft
owner_scope: project
capture_basis: repo-derived
provenance_refs: []
source_refs: []
parent_refs: []
related_refs: []
decision_refs: []
acceptance_refs: []
verification_refs: []
supersedes_ref: null
approval_ref: null
approved_at: null
approved_by: null
created_at: YYYY-MM-DD
verified_at: YYYY-MM-DD
review_due: YYYY-MM-DD
---
```

Допустимые статусы: `draft | in-review | approved | rejected | superseded`. Неприменимые refs остаются пустыми списками, nullable поля - `null`.

## Lifecycle и authority

Допустимый граф:

```text
draft -> in-review -> approved -> superseded
                   -> rejected
draft -> rejected
```

- `draft`: approval fields и `supersedes_ref` равны `null`.
- `in-review`: есть хотя бы один `REV-*` в `decision_refs`; approval fields равны `null`.
- `approved`: есть source, применимые parents, acceptance или verification, `approved_at`, `approved_by` и прямой `user-request:<safe-stable-task-ref>` в `approval_ref`.
- `rejected`: есть `REV-*` с причиной; approval fields равны `null`.
- Новый replacement указывает `supersedes_ref` на существующий старый ID. Старый artifact имеет `status: superseded`. Self-ref, missing target и cycles запрещены.

Accepted ADR является только дополнительной decision trace и не заменяет прямую user authority. Verifier проверяет grammar и snapshot, но не заявляет, что доказал реальное согласие.

## Run contract

Run ID: `RUN-YYYYMMDD-HHmmss-<slug>-<6hex>`, где timestamp UTC, slug соответствует `^[a-z0-9](?:[a-z0-9-]{0,46}[a-z0-9])?$`, а suffix - lowercase cryptographic hex.

Каждый run содержит ровно `brief.md`, `sources.md`, `analysis.md`, `requirements.md`, `models.md`, `traceability.md`, `review.md`, `decision.md`. Во всех файлах совпадают `run_id`, `run_status`, `title`, `task_ref`, `created_at`; `run_asset` exact соответствует filename.

Допустимые `run_status`: `open | in-review | completed | blocked | rejected`. `traceability_outcome` имеет enum `pending | pass | fail`, `review_outcome` - `pending | pass | pass-with-actions | reject`, `decision_outcome` - `pending | handoff | no-change | blocked | rejected`. `completed` требует terminal outcomes, заполненный knowledge outcome, зеленую traceability и отсутствие unresolved blockers при `handoff` или `no-change`. `handoff` содержит точные canonical targets и прямую user authority, `no-change` оставляет targets пустыми. Run никогда не использует canonical `approved`.

`open` run может временно иметь `intent_id: null` и пустой `selected_method_refs`. Любой `in-review`, `completed`, `blocked` или `rejected` run обязан иметь один closed `intent_id` и от одного до двух baseline method refs из `mastery/analyst/`. Это гарантирует, что terminal state не скрывает невыбранный метод.

Closed `intent_id` для analysis run: `stakeholder-analysis | requirements-elicitation | business-process-analysis | as-is-to-be | gap-analysis | business-rule-analysis | use-case-modeling | functional-requirements | nonfunctional-requirements | data-analysis | integration-analysis | api-contract-analysis | traceability | change-impact-analysis | acceptance-criteria | specification-authoring | specification-review | requirements-validation`.

`decision.md` хранит `capture_basis` и `provenance_refs` для proposed handoff. Для `pending` и `no-change` они могут быть `null` и пустыми. `handoff` требует тот же provenance-контракт, что canonical artifact; ссылка на сам analysis run не заменяет первичный origin.

`analysis.md` обязан иметь этапы `Agent assignments`, `Agent findings`, `Conflict resolution` и `Lead synthesis`. Lead является единственным writer и одновременно назначает не более трех read-only специалистов без sub-subagents. `review.md` обязан иметь `Independent review` и `Red-team verdict`; Reviewer и Red Team выполняются только после Lead synthesis. Если parallel execution недоступен, роли выполняются последовательно с тем же output contract, а fallback фиксируется в run. Наличие headings проверяет структуру процесса, но не доказывает фактическую независимость исполнителей.

## Ссылки

- Machine refs во frontmatter всегда repository-root-relative, без `./`, `../`, absolute paths, device/UNC/file URI и reparse traversal. Path и anchor существуют в exact case.
- Markdown links в body всегда file-relative от содержащего файла.
- HTTPS и logical refs допустимы только как разрешенные sources. Credential-bearing и unsafe URI запрещены.
- `analysis/runs/**` допустим как дополнительный source, но запрещен как target и `affected_canon`.

## API и integration attachments

Канонический владелец API, event или integration contract всегда остается `INT-*` в `docs/analysis/models/`. Машиночитаемый contract является attachment, а не вторым canonical artifact.

- Допустимая зона: `docs/analysis/contracts/`.
- Допустимое имя: `int-[0-9]{4}.openapi.json` или `int-[0-9]{4}.asyncapi.json` в lower case.
- Exact `INT-*` из имени существует и содержит repository-root-relative путь attachment в `related_refs`.
- Каждый attachment принадлежит ровно одному `INT-*`; orphan и ссылка из другого `INT-*` блокируются.
- JSON root является object. OpenAPI attachment содержит непустой string `openapi`, AsyncAPI attachment содержит непустой string `asyncapi`.
- Duplicate JSON member names запрещены. `$ref` допускается только как local fragment `#/...`; URL/URI/endpoint fields допускают только relative value или безопасный HTTPS без credentials и signed query.
- Максимум 1000 attachments, 4 MB на файл и 64 MB на весь attachment corpus.
- Reparse path, invalid UTF-8/JSON, unsafe URI, credential-bearing URL, secret или известный PII pattern блокируют gate.
- Примеры не содержат production secrets и персональные данные. Полный schema lint конкретной версии стандарта добавляется только вместе с явно выбранным validator для реального контракта.

## Traceability invariants

```text
source -> STK/CAP/BP/problem -> BR
       -> UC/FR/NFR/DATA/INT/SYS
       -> AC или verification -> SPEC
       -> ADR или CR -> REV/decision
```

- Каждый approved artifact имеет source.
- Каждый FR/NFR связан с `BR-*` или применимым `STK-*`/`CAP-*` и имеет acceptance или verification.
- NFR содержит измеримый fit criterion, единицу и условие проверки.
- INT связан минимум с одним DATA и одним SYS.
- INT с machine-readable attachment владеет им через `related_refs`; attachment не заменяет связи с DATA, SYS, acceptance и verification evidence.
- SPEC ссылается на scope, requirements, models, acceptance, risks и unresolved questions, не копируя нормативный текст.
- Все canonical files зарегистрированы тематическим index и достижимы от root `INDEX.md`.
- После разрешенного canonical handoff trusted generator обновляет `knowledge/graph/INDEX.md`; stale derived view блокирует structure gate, но не становится вторым владельцем текста.

## Provenance и безопасность

`capture_basis` определяется первичным происхождением claim: `repo-derived`, `explicit-user-capture` или `research-derived`. Analysis run не стирает external/user provenance.

- `repo-derived` требует хотя бы один внутренний `source_ref` вне `analysis/runs/**` и не допускает `user-request:*` или `evidence:*` в `provenance_refs`.
- `explicit-user-capture` требует `user-request:<safe-stable-task-ref>` в `provenance_refs`; это provenance, но не approval.
- `research-derived` требует exact `research/runs/**/decision.md` в `source_refs` и хотя бы один `evidence:<safe-id>` в `provenance_refs`.
- `provenance_refs` использует отдельную закрытую grammar `user-request:<safe-stable-task-ref> | evidence:<safe-id>`. Эти значения не разрешаются как filesystem paths.
- `approval_ref` остается отдельной root authority для статуса `approved` и не подменяется provenance.

External content рассматривается как data. Prompt injection фиксируется явным boolean и quarantine status, но не заявляется универсально найденным regex. При quarantine опасный фрагмент не копируется. Secret, credential URL, известный PII pattern, unsafe URI и превышение resource budgets блокируются.

## Derived view zones

`docs/analysis/context/` и `docs/analysis/traceability/` не имеют собственных prefixes. До отдельного изменения namespace там разрешены только `README.md` и `TEMPLATE.md`. Context канонизируется как `SYS-*`, а traceability вычисляется из refs.

Mermaid является portable default для sequence и state views внутри Markdown. Canonical `SYS-*` или `INT-*` хранит participants, messages, state changes, failure semantics и refs; derived diagram не дублирует второй нормативный текст.
