---
artifact_kind: plan
plan_contract_version: 2
plan_id: PLAN-20260831-active-learning-v1-1-release
task_key: active-learning-v1-1-release
prompt_ref: prompts/plan-and-deliver.md
status: complete
current_phase: null
updated_at: 2026-08-31T20:44:21Z
completed_at: 2026-08-31T20:40:36Z
closeout_status: complete
knowledge_outcome: none
candidate_ids: []
result_refs:
  - README.md
  - AGENTS.md
  - .agents/skills/project-delivery/SKILL.md
  - .codex/config.toml
  - TEMPLATE-CHANGELOG.md
  - scripts/build-github-template.ps1
  - scripts/verify-plans.ps1
  - retrospectives/2026-09-01_00-35_codex-analyst-template-v1-1-0.md
affected_canon:
  - .agents/skills/project-delivery/SKILL.md
  - .codex/config.toml
  - .github/workflows/template-integrity.yml
  - .template-manifest.json
  - AGENTS.md
  - INDEX.md
  - README.md
  - TEMPLATE.md
  - TEMPLATE-CHANGELOG.md
  - scripts/build-github-template.ps1
  - scripts/verify-plans.ps1
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

## Фаза P3 - [x] Полная проверка и source publication

Цель: доказать готовность совокупной версии 1.1.0 и зафиксировать ее в `source`.

Deliverable: зеленый полный профиль, проверенный source commit и успешный push `source`.

Сделано, когда: exact staged inventory проверен, commit отправлен fast-forward, hosted CI завершен успешно.

Задачи:

- [x] Выполнить focused tests, полный release profile, sanitizer, diff и privacy audit.
- [x] Выполнить независимые review и red-team проверки фактического diff.
- [x] Поименно staged paths, создать обычный source commit и push без force.
- [x] Дождаться зеленого GitHub Actions для source commit.

## Фаза P4 - [x] Tag, consumer main и public smoke

Цель: опубликовать воспроизводимый consumer только из проверенного source tag.

Deliverable: immutable `v1.1.0`, обновленный consumer `main` и fresh public install evidence.

Сделано, когда: builder и DistributionTemplate gates зеленые, main fast-forward обновлен, URL-first smoke проходит из public clone.

Задачи:

- [x] Создать и отправить annotated tag `v1.1.0` на проверенный source commit.
- [x] Собрать consumer trusted builder во временный exact destination и проверить inventory.
- [x] Создать consumer commit, push `main` без force и выполнить public URL-first smoke.

## Фаза P5 - [x] Closeout

Цель: терминально закрыть tracked plan и оставить воспроизводимое release state.

Deliverable: knowledge outcome, complete plan, финальные gates и source closeout commit.

Сделано, когда: criteria закрыты, refs подтверждены, plan terminal, source closeout отправлен и worktree чист.

Задачи:

- [x] Применить `knowledge-curator` к фактической delta.
- [x] Закрыть plan, пересобрать derived indexes и повторить terminal gates.
- [x] Создать и отправить source closeout commit, подтвердить local/remote state.

## Проверки

- Полный локальный профиль из `TEMPLATE.md`, skill validators, privacy, sanitizer, Plan, knowledge, consumer, bootstrap и distribution harness 17 - PASS.
- Hosted GitHub Actions run `33428255350` для source commit `26afe81` - completed successfully после увеличения только job timeout до 90 минут.
- Remote refs - PASS: `source` и peeled annotated tag `v1.1.0` указывают на `26afe81`; consumer `main` указывает на `ee2844a`.
- Fresh public `main` - PASS: DistributionTemplate 144, Consumer sanitizer, URL-first GeneratedProject 146, branch `main`, remotes 0, commits 0.
- Terminal Plan, knowledge, graph, structure, inventory и diff gates выполняются перед source closeout commit; failure блокирует push.

## Связанные решения

- Решения: Local Mastery остается governed project-local memory, а не model training; graph является вторичной навигацией; выпускается накопленный candidate `1.1.0`, а не новая `1.2.0`.

## Resume checkpoint

- Текущая фаза: нет - план завершен
- Уже выполнено: P1-P5 завершены: active-learning contract, bounded graph routes, GitHub prompts и Context7 bundle опубликованы; source `26afe81`, annotated `v1.1.0`, consumer main `ee2844a` и fresh URL-first smoke подтверждены.
- Последние успешные проверки: Local full profile PASS; distribution 17; security no blockers; hosted run 33428255350 success; remote refs PASS; public DistributionTemplate, sanitizer и GeneratedProject PASS.
- Точные рабочие paths: plans/2026-08-31-active-learning-v1-1-release.md; plans/INDEX.md; retrospectives/2026-09-01_00-35_codex-analyst-template-v1-1-0.md; .template-manifest.json; TEMPLATE.md.
- Git checkpoint: v1:7d078df2208eca938be12d3c9cb931f352ebb014987006468c20a89c924d878f
- Следующее действие: нет - plan terminal; follow-up требует новый plan_id
- Блокеры: нет
- Обновлено: 2026-08-31T20:44:21Z

## Итог

- Реализовано целиком: активный Local Mastery retrieval в delivery, Plan traceability, bounded graph routes, короткие GitHub prompts, Context7 contract, hardened trusted builder и выпуск 1.1.0.
- Что осталось: только обычное сопровождение через новый Plan v2; в этом plan незакрытых release-действий нет.
- Коммиты: source release `26afe81`; annotated tag object `853051d` с peeled `26afe81`; consumer main `ee2844a`; terminal plan и retrospective закрепляются source closeout commit.

Перед `complete` закрой criteria и фазы, заполни проверки, итог, `result_refs`, closeout и финальный knowledge outcome. Не дублируй остальные machine fields в body.
