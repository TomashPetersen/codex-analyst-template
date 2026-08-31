---
artifact_kind: plan
plan_contract_version: 2
plan_id: PLAN-20260831-active-learning-v1-1-release
task_key: active-learning-v1-1-release
prompt_ref: prompts/plan-and-deliver.md
status: in-progress
current_phase: P3
updated_at: 2026-08-31T18:57:25Z
completed_at: null
closeout_status: pending
knowledge_outcome: null
candidate_ids: []
result_refs: []
affected_canon: []
blocked_reason: null
---

# План: Активное обучение, GitHub prompts и выпуск 1.1.0

## Цель

Замкнуть минимальный цикл повторного применения Local Mastery, добавить короткие GitHub-промты установки и работы, затем выпустить накопленный candidate как `1.1.0` в `source`, tag `v1.1.0` и consumer `main`.

## Метод выполнения

- Intent ID: release
- Local method ID: none
- Local method ref: none

## Границы

Входит:

- обязательный выбор intent и максимум одного применимого local method в `project-delivery` с проверяемой фиксацией в Plan v2;
- условный read-only маршрут по knowledge graph только для cross-domain discovery, impact, traceability, backlinks, conflicts и duplicate search;
- два коротких copy-ready промта в README: URL-first установка и работа с локальным пространством после установки;
- сохранение и выпуск уже завершенной Context7-дельты текущего worktree вместе с минимальными дополнениями;
- финализация `1.1.0`, полный gate, точечный staging, обычные commits и push без force;
- immutable tag `v1.1.0`, сборка consumer из tag и обновление `main` после зеленого source CI.

Не входит:

- обучение весов модели, фоновая память или automatic promotion;
- автоматический выбор просроченного, deprecated или superseded метода;
- превращение knowledge graph в источник истины или универсальный first-read;
- новые MCP, plugins, connectors, models, dependencies или GitHub Release object;
- изменение GitHub settings, default branch, истории `v1.0.0` и `v1.0.1`, force push или deploy.

## Критерии приемки

1. Новый Plan v2 явно хранит `Intent ID` и `Local method ref`; verifier принимает `none` либо один существующий active, непросроченный метод, применимый к intent, и сохраняет совместимость с completed historical plans.
2. `project-delivery` до предметной записи читает intent catalog и Local Mastery, выбирает максимум один метод и не использует graph для проверки applicability или срока.
3. Корневые инструкции открывают graph только для bounded cross-domain discovery/impact/traceability/backlinks/conflicts/duplicate search, а затем ведут к точным owner artifacts.
4. README содержит два коротких самодостаточных промта, которые можно скопировать со страницы GitHub без ручного изучения внутреннего процесса.
5. Версия `1.1.0` согласована в manifest, changelog, source contract и consumer; current published release больше не указан как `v1.0.1`.
6. Полный локальный профиль и hosted source CI зеленые; tag указывает на проверенный source commit, consumer `main` собран trusted builder только из этого tag.
7. `origin/source`, `origin/main` и `refs/tags/v1.1.0` подтверждены независимо; staging и worktree в конце чисты, push выполнен без force.

## Риски, безопасность и откат

- Existing Context7-дельта принадлежит предыдущим завершенным plans и не отделяется destructive reset; перед commit проверяется полный совокупный diff.
- Изменение Plan contract может сломать historical plans или fresh bootstrap; обратная совместимость и negative fixtures обязательны.
- Local method остается агентным выбором, поэтому gate доказывает допустимость выбранной ссылки, но не semantic оптимальность; fallback равен `none`.
- Remote может измениться между проверкой и push. Любой non-fast-forward, CI failure или tag collision блокирует выпуск без force.
- Trusted builder использует detached snapshot exact tag commit, игнорирует replacement refs и перед atomic publish повторно подтверждает provenance portable payload; regression gates обязаны отклонять primary drift и mutation от tagged indexer.
- До push изменения обратимы обычной правкой. После push допустим только новый корректирующий commit; удаление refs и переписывание истории не входят в scope.

## Фаза P1 - [x] Контракт и preflight

Цель: закрепить минимальный scope, release authority и безопасное продолжение dirty worktree.

Deliverable: активный Plan v2, зарегистрированный в source inventory, и подтвержденная remote/version topology.

Сделано, когда: plan gate зеленый, existing delta атрибутирована завершенным plans, remote refs проверены read-only.

Задачи:

- [x] Зарегистрировать plan как source-only history и проверить Plan v2.
- [x] Подтвердить remote `source`, `main`, tags и отсутствие `v1.1.0`.
- [x] Зафиксировать выбранный intent `release` и отсутствие local methods в пустом template.

## Фаза P2 - [x] Минимальная реализация и GitHub prompts

Цель: замкнуть retrieval loop и упростить onboarding без расширения архитектуры.

Deliverable: согласованные skill, Plan body contract/verifier/tests, graph routes и README prompts.

Сделано, когда: positive и negative fixtures доказывают выбор метода, routes не меняют owner authority, тексты остаются краткими.

Задачи:

- [x] Добавить intent/local method preflight и Plan traceability.
- [x] Добавить условный graph route в `AGENTS.md` и `INDEX.md`.
- [x] Добавить два copy-ready prompts и синхронизировать release docs/version.

## Фаза P3 - [WIP] Полная проверка и source publication

Цель: доказать готовность совокупной версии 1.1.0 и зафиксировать ее в `source`.

Deliverable: зеленый полный профиль, проверенный source commit и успешный push `source`.

Сделано, когда: exact staged inventory проверен, commit отправлен fast-forward, hosted CI завершен успешно.

Задачи:

- [x] Выполнить focused tests, полный release profile, sanitizer, diff и privacy audit.
- [x] Выполнить независимые review и red-team проверки фактического diff.
- [ ] Поименно staged paths, создать обычный source commit и push без force.
- [ ] Дождаться зеленого GitHub Actions для source commit.

## Фаза P4 - [ ] Tag, consumer main и public smoke

Цель: опубликовать воспроизводимый consumer только из проверенного source tag.

Deliverable: immutable `v1.1.0`, обновленный consumer `main` и fresh public install evidence.

Сделано, когда: builder и DistributionTemplate gates зеленые, main fast-forward обновлен, URL-first smoke проходит из public clone.

Задачи:

- [ ] Создать и отправить annotated tag `v1.1.0` на проверенный source commit.
- [ ] Собрать consumer trusted builder во временный exact destination и проверить inventory.
- [ ] Создать consumer commit, push `main` без force и выполнить public URL-first smoke.

## Фаза P5 - [ ] Closeout

Цель: терминально закрыть tracked plan и оставить воспроизводимое release state.

Deliverable: knowledge outcome, complete plan, финальные gates и source closeout commit.

Сделано, когда: criteria закрыты, refs подтверждены, plan terminal, source closeout отправлен и worktree чист.

Задачи:

- [ ] Применить `knowledge-curator` к фактической delta.
- [ ] Закрыть plan, пересобрать derived indexes и повторить terminal gates.
- [ ] Создать и отправить source closeout commit, подтвердить local/remote state.

## Проверки

- Focused: `scripts/test-plan-lifecycle.ps1`, `scripts/verify-plans.ps1`, `scripts/update-knowledge-graph.ps1 -Mode Check`.
- Полный профиль из `TEMPLATE.md`, включая analysis, agents, mastery, knowledge, consumer boundary, bootstrap, distribution и sanitizer.
- `git diff --check`, staged inventory, secret/PII/source-only leakage audit.
- Hosted GitHub Actions source matrix и fresh public `main` URL-first bootstrap.

## Связанные решения

- Решения: Local Mastery остается governed project-local memory, а не model training; graph является вторичной навигацией; выпускается накопленный candidate `1.1.0`, а не новая `1.2.0`.

## Resume checkpoint

- Текущая фаза: P3
- Уже выполнено: Release commit bf8703f отправлен fast-forward в source. Hosted run 33419990968: macOS PASS за 57m19s; Windows отменен только job timeout 60m после 1h0m15s. CI timeout увеличен до 90m без изменения gates.
- Последние успешные проверки: Source local profile PASS; distribution checks=17; security review no blockers; exact staging 37 paths; credential audit PASS; source push bf8703f; macOS hosted PASS; Windows tests не сообщили failure до timeout.
- Точные рабочие paths: .github/workflows/template-integrity.yml; plans/2026-08-31-active-learning-v1-1-release.md; plans/INDEX.md.
- Git checkpoint: v1:8dab1e9fdf1f3ca40291b46211065ecc1b4aab53328e4002b5739029d54f4b20
- Следующее действие: Проверить one-line CI diff, создать corrective source commit, push без force и дождаться зеленого Windows/macOS rerun.
- Блокеры: нет: timeout cause подтвержден публичными job pages
- Обновлено: 2026-08-31T18:57:25Z

## Итог

- Реализовано целиком:
- Что осталось: P1-P5.
- Коммиты: пока нет.

Перед `complete` закрой criteria и фазы, заполни проверки, итог, `result_refs`, closeout и финальный knowledge outcome. Не дублируй остальные machine fields в body.
