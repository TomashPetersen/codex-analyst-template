---
artifact_kind: plan
plan_contract_version: 2
plan_id: PLAN-20260820-codex-analyst-template-v1
task_key: codex-analyst-template-v1
prompt_ref: prompts/plan-and-deliver.md
status: complete
current_phase: null
updated_at: 2026-08-22T06:52:50Z
completed_at: 2026-08-22T06:52:50Z
closeout_status: complete
knowledge_outcome: none
candidate_ids: []
result_refs:
  - README.md
  - analysis/CONTRACT.md
  - .codex/config.toml
  - scripts/verify-structure.ps1
  - retrospectives/2026-08-21_19-27_codex-analyst-template-v1.md
affected_canon:
  - AGENTS.md
  - analysis/CONTRACT.md
  - knowledge/INDEX.md
  - mastery/analyst/INDEX.md
blocked_reason: null
---

# План: Codex Analyst Template v1.0.0

## Цель

Создать публично-безопасный русскоязычный GitHub Template для системного и бизнес-анализа: с Plan v2, формальным аналитическим контуром, read-only ролями Codex, переносимыми skills, mastery, lifecycle знаний и воспроизводимыми проверками.

## Границы

Входит:

- перенос нейтрального control plane из зафиксированного состояния базового шаблона;
- восстановление formal-analysis из неизменяемого release tag и перенос только универсальных улучшений из доменного проекта;
- пять project-scoped read-only ролей, четыре project-local skills и маршрутизирующие prompts;
- продуктовый, бизнес-, архитектурный, research, knowledge, mastery и delivery контуры;
- GitHub distribution, Windows bootstrap, macOS CI и проверка fresh generated copy;
- обезличивание source и consumer payload.

Не входит:

- перенос заполненного предметного канона, runs, RAW, candidates, local mastery, retrospectives, графа, origin или Git-истории исходных проектов;
- настройка MCP, plugins, connectors, automations, secrets или моделей;
- commit, tag, push, deploy, публикация GitHub и запись во внешнюю память.

## Критерии приемки

1. Корневой `AGENTS.md` self-contained и маршрутизирует роли, Plan v2, analysis runs, knowledge lifecycle и authority.
2. Fresh generated project содержит весь заявленный контур, запускает все verifiers и не содержит source-only материалов.
3. Один analysis run атомарно создается с восемью файлами и проходит 86 исходных сценариев self-test плюс новые интеграционные проверки.
4. `.codex/config.toml` ограничивает параллелизм тремя специалистами; все пять project agents read-only, не выбирают модель и не создают subagents.
5. Knowledge lifecycle сохраняет `ready -> applied | dismissed`, обязательный backlink, noise budget и запрет automatic promotion; граф включает канон и formal-analysis, но исключает runs, plans, RAW и retrospectives.
6. Manifest точно описывает payload, Analyst Mastery входит в immutable baseline, а 18 closed analysis intents покрыты.
7. Sanitize gate не находит доменных следов, персональных данных, credentials, абсолютных пользовательских путей, UUID и commit SHA в разрешенной области проверки.
8. Source подготовлен к веткам `source`/`main` и tag `v1.0.0`, но никакая release-операция не выполнена.

## Риски, безопасность и откат

- Риск загрязнения исходными данными снижается allowlist-импортом, отдельным sanitize gate и consumer-boundary test.
- Риск расхождения между manifest, graph и canon снижается детерминированными генераторами и check-mode gates.
- Риск записи специалистами снижается `sandbox_mode = "read-only"`, single-writer контрактом и отдельной статической проверкой `.codex`.
- Откат до первого commit выполняется точечным удалением только созданных путей после отдельного подтверждения; в рамках этой задачи destructive rollback не выполняется.

## Фаза P1 - [x] Bootstrap и Plan v2

Цель: получить нейтральный control plane и активный единый план без переноса Git-истории.

Deliverable: allowlisted baseline и зеленый Plan v2 lifecycle.

Сделано, когда: создан этот plan, индекс детерминирован, `verify-plans.ps1` и resume assertion проходят.

Задачи:

- [x] Зафиксировать исходное состояние `NO_HEAD` и пустой diff baseline.
- [x] Импортировать allowlisted baseline из exact source HEAD.
- [x] Удалить нерелевантную source-only историю из нового шаблона.
- [x] Проверить plan lifecycle и checkpoint.

## Фаза P2 - [x] Формальный аналитический контур

Цель: объединить immutable formal-analysis baseline с нейтральными универсальными улучшениями.

Deliverable: analysis run, formal canon, method references, attachments и обновленные gates.

Сделано, когда: `verify-analysis.ps1 -SelfTest` проходит все fixtures, а owner boundaries согласованы.

Задачи:

- [x] Восстановить formal-analysis из точного release tag.
- [x] Перенести только обезличенные универсальные улучшения.
- [x] Пересобрать нейтральные индексы и шаблоны.
- [x] Добавить все 18 closed analysis intents в mastery registry.

## Фаза P3 - [x] Multi-agent и prompts

Цель: зафиксировать проверяемую read-only оркестрацию с одним writer.

Deliverable: `.codex/config.toml`, пять ролей, обновленный `it-analysis` и четыре маршрута prompts.

Сделано, когда: static TOML gate и role fixtures проходят, а последовательный fallback документирован.

Задачи:

- [x] Добавить project-scoped agent configs без моделей, MCP и расширения прав.
- [x] Зафиксировать максимум трех специалистов и запрет sub-subagents.
- [x] Добавить exact `plan_policy` для bounded run, program, review и handoff.

## Фаза P4 - [x] Knowledge, canon и память проекта

Цель: объединить formal-analysis с существующим knowledge lifecycle без смешения владельцев.

Deliverable: согласованные manifests, canon gates, mastery baseline и knowledge graph.

Сделано, когда: graph включает formal canon, исключает эфемерные классы и все backlinks/lifecycle fixtures зеленые.

Задачи:

- [x] Развести владельцев product, business, architecture и formal-analysis.
- [x] Удалить специальные внешние mastery routes.
- [x] Обновить graph, manifest и immutable baseline.

## Фаза P5 - [x] Обезличивание и distribution

Цель: выпустить нейтральный source и воспроизводимый GitHub consumer payload.

Deliverable: README, PROJECT, INDEX, install prompt, license/notices, CI, sanitizer и boundary tests.

Сделано, когда: sanitize scan, exact manifest inventory, bootstrap и distribution roundtrip проходят.

Задачи:

- [x] Обновить публичную документацию и version contract `1.0.0`.
- [x] Добавить source/consumer privacy и boundary gates.
- [x] Проверить пустые RAW, candidates, runs и local mastery.

## Фаза P6 - [x] Независимая проверка и closeout

Цель: получить evidence-backed приемку без release-действий.

Deliverable: полный gate report, независимый review, retrospective и terminal plan.

Сделано, когда: все локально доступные проверки зеленые, findings закрыты или явно отражены, plan завершен.

Задачи:

- [x] Выполнить AST, diff, structure, canon, mastery, knowledge, privacy, graph и consumer gates.
- [x] Проверить fresh initialized copy и synthetic analysis run.
- [x] Выполнить независимый review единственным разрешенным субагентом.
- [x] Провести knowledge closeout и завершить plan.

## Проверки

- PowerShell AST - PASS для 37 файлов `.ps1` и `.psm1`; `git diff --check` и отдельный `git diff --no-index --check` - PASS для 205 untracked-файлов.
- Plan v2 lifecycle, resume drift fixtures, platform helpers, mastery index, plan index и knowledge graph check - PASS.
- `verify-analysis.ps1 -SelfTest` - 86 сценариев PASS; текущий analysis report - `canon=0`, `runs=0`, `issues=0`.
- `verify-codex-agents.ps1 -SelfTest` - 5 сценариев PASS; текущий report - пять read-only ролей и concurrency cap 3.
- Knowledge suites - artifacts 15/15, privacy 37 bounded checks, research 12 requested cases, mastery 24/24, control-plane P0 и полный `verify-knowledge.ps1 -SelfTest` PASS; текущий report - 0 candidates, conflicts и drift.
- Canon, graph, sanitizer self-tests и текущие source gates - PASS; sanitize охватил 205 файлов.
- Consumer boundary - PASS, `portable=184`; manifest - 184 portable, 21 source-only и 15 immutable mastery files.
- GitHub distribution roundtrip - 14/14 PASS; cross-platform bootstrap harness - PASS.
- Fresh generated copy - structure PASS, 145 canonical Markdown-файлов; synthetic analysis run создан атомарно и содержит ровно восемь файлов.
- Независимый read-only review - findings отсутствуют, confidence high, SHA дерева до и после review совпал.
- Финальный TemplateSource structure gate - PASS, 148 canonical Markdown-файлов.

## Связанные решения

- Решения: этот plan является единственным execution contract; release authority не предоставлена.

## Resume checkpoint

- Текущая фаза: нет - план завершен
- Уже выполнено: P1-P6 выполнены; retrospective и knowledge closeout зафиксированы с outcome none; release actions не выполнялись.
- Последние успешные проверки: PASS: AST 37; diff-check 205 untracked; analysis 86; agents 5; knowledge full suites; distribution 14/14; consumer 184; sanitizer 205; TemplateSource structure 148; fresh copy и read-only review.
- Точные рабочие paths: plans/2026-08-20-codex-analyst-template-v1.md; retrospectives/2026-08-21_19-27_codex-analyst-template-v1.md; .template-manifest.json; scripts/; .codex/; analysis/; mastery/; knowledge/
- Git checkpoint: v1:c15f85263fdc7a1cd77eea1e96c5dbfbe0cecd16ae821a3d87e629dfbfd07b59
- Следующее действие: нет - plan terminal; follow-up требует новый plan_id
- Блокеры: нет
- Обновлено: 2026-08-22T06:52:50Z

## Итог

- Реализовано целиком: публично-безопасный русскоязычный Codex Analyst Template v1.0.0 с formal-analysis, Plan v2, пятью read-only ролями, четырьмя skills, mastery, knowledge lifecycle, bootstrap, distribution и проверяемым consumer payload.
- Что осталось: только фактический запуск macOS CI и release-действия после отдельной команды владельца; локальная подготовка завершена.
- Коммиты: отсутствуют; репозиторий остается без HEAD, tag, remote и push.

Перед `complete` закрой criteria и фазы, заполни проверки, итог, `result_refs`, closeout и финальный knowledge outcome. Не дублируй остальные machine fields в body.
