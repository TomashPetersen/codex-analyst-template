---
artifact_kind: plan
plan_contract_version: 2
plan_id: PLAN-20260823-github-release-v1-0-0
task_key: github-release-v1-0-0
prompt_ref: prompts/plan-and-deliver.md
status: complete
current_phase: null
updated_at: 2026-08-28T07:23:08Z
completed_at: 2026-08-28T07:23:08Z
closeout_status: complete
knowledge_outcome: none
candidate_ids: []
result_refs:
  - TEMPLATE-CHANGELOG.md
  - retrospectives/2026-08-28_11-20_github-release-v1-0-1.md
affected_canon:
  - .template-manifest.json
  - README.md
  - TEMPLATE-DISTRIBUTION.json
  - TEMPLATE.md
  - TEMPLATE-CHANGELOG.md
blocked_reason: null
---

# План: GitHub release Codex Analyst Template v1.0.0 и corrective v1.0.1

## Цель

Опубликовать проверенный Codex Analyst Template в публичном repository `https://github.com/TomashPetersen/codex-analyst-template` с source branch, производной consumer branch `main`, неизменяемым исходным tag `v1.0.0`, корректирующим tag `v1.0.1`, GitHub Template metadata и подтвержденной установкой по реальному URL.

## Границы

Входит:

- создать точную tracked source history из текущего no-HEAD snapshot;
- выполнить полный локальный release profile до tag и push;
- создать branch `source`, tag `v1.0.0` и производную unrelated branch `main` только из portable payload;
- сохранить `v1.0.0` неизменным, выпустить corrective tag `v1.0.1` после green hosted matrix и пересобрать `main` из него;
- отправить `main`, `source` и tags в указанный GitHub repository без force push;
- сделать `main` default branch, включить GitHub Template и установить нейтральное About description;
- проверить публичный clone, URL-first bootstrap и GitHub Actions;
- завершить release retrospective, knowledge closeout и terminal Plan v2 в отдельном post-release source commit.

Не входит:

- изменение содержимого published tag после создания;
- публикация secrets, PII, RAW, заполненных runs, candidates или source-only материалов в `main`;
- настройка MCP, plugins, connectors, models или продукта пользователя;
- GitHub Release binaries, package registry, deployment приложения или удаление веток;
- force push, переписывание remote history или обход обязательного gate.

## Критерии приемки

1. Target repository существует, публичен, пуст до первого push и совпадает с exact GitHub identity `TomashPetersen/codex-analyst-template`.
2. Source release commit находится на branch `source`, включает точный manifest inventory и проходит полный профиль из `TEMPLATE.md`.
3. Annotated tag `v1.0.0` продолжает указывать на исходный source release commit; annotated tag `v1.0.1` указывает на exact corrective source release commit; оба tag неизменяемы.
4. Builder создает consumer payload из source tag `v1.0.1`, descriptor содержит правильные source commit, tag, repository URL и SHA-256 portable-файлов.
5. Remote `main` имеет отдельный root commit и содержит только consumer payload: 185 portable-файлов, `distribution-template + template + disabled`, без source-only paths.
6. Remote содержит `main`, `source`, `refs/tags/v1.0.0` и `refs/tags/v1.0.1`; default branch равна `main`, repository включен как GitHub Template, About description содержит URL-first инструкцию.
7. GitHub Actions source matrix для Windows и macOS завершается успешно либо выпуск блокируется с точной внешней причиной без ослабления gates.
8. Fresh public clone `main` и URL-first `new-project.ps1` создают независимый `generated-project + initialized + report-only`, Git `main` без remote и зеленый structure gate.
9. Финальный sanitizer, privacy, knowledge, diff и inventory audit не обнаруживает secrets, PII, source-only leakage или незаявленные файлы.
10. Release plan и retrospective завершены в post-release source commit; knowledge outcome равен `none`, если новый устойчивый claim уже закреплен release-контрактом.

## Риски, безопасность и откат

- External write ограничен exact repository URL, branches `main` и `source`, tags `v1.0.0` и `v1.0.1`, About и template setting.
- GitHub repository проверяется пустым до первого push; любое неожиданное remote ref блокирует публикацию.
- `main` строится только trusted builder из exact source tag и не копируется вручную.
- Push выполняется без `--force`; partial remote state исправляется только добавлением недостающих refs или settings, без переписывания опубликованных commits.
- Credentials предоставляет штатный Git Credential Manager или существующая browser session; token и secret не читаются и не выводятся.
- Tag создается только после локальных gates. После push rollback требует отдельной destructive authority и в эту задачу не входит.

## Фаза P1 - [x] Preflight и release contract

Цель: подтвердить target, authority, baseline и воспроизводимый порядок выпуска.

Deliverable: active Plan v2, exact remote identity, source-only registration и release sequence.

Сделано, когда: remote пуст, baseline зафиксирован, plan/manifest/maintenance links согласованы и Plan gate зеленый.

Задачи:

- [x] Зафиксировать no-HEAD snapshot без изменения index.
- [x] Подтвердить пустой remote через `git ls-remote`.
- [x] Выбрать порядок source commit/tag -> consumer build -> `main` first push -> `source`/tag -> post-release closeout.
- [x] Зарегистрировать plan в source-only manifest и maintenance graph.

## Фаза P2 - [x] Source release candidate

Цель: получить clean tracked source commit и immutable release tag после полного локального профиля.

Deliverable: branch `source`, source release commit и annotated tag `v1.0.0`.

Сделано, когда: все source gates зеленые, exact paths staged поименно, source worktree clean и tag указывает на HEAD.

Задачи:

- [x] Выполнить AST, diff, structure, analysis, agents, plans, canon, mastery, knowledge, privacy, bootstrap и distribution suites.
- [x] Создать branch `source`, настроить exact origin и выполнить первый source commit без broad add.
- [x] Создать и проверить annotated tag `v1.0.0`.

## Фаза P3 - [x] Consumer main

Цель: собрать и независимо проверить GitHub Template payload из tagged source.

Deliverable: временный clean Git repository с unrelated branch `main` и consumer commit.

Сделано, когда: builder и DistributionTemplate gates зеленые, inventory exact и source-only paths отсутствуют.

Задачи:

- [x] Собрать payload trusted builder в точный temporary destination.
- [x] Проверить descriptor, hashes, sanitizer, boundary и independent URL-first bootstrap.
- [x] Создать consumer root commit на `main` без source history.

## Фаза P4 - [x] GitHub publication и corrective release

Цель: опубликовать refs и repository settings без force или скрытого external write.

Deliverable: публичные `main`, `source`, неизменяемые `v1.0.0` и `v1.0.1`, default `main`, template flag и About.

Сделано, когда: remote refs и settings подтверждены независимо, а GitHub Actions source matrix зеленая.

Задачи:

- [x] Повторно подтвердить пустой remote и отправить consumer `main` первым.
- [x] Отправить source branch и immutable tag без force.
- [x] Настроить default branch, GitHub Template и About через авторизованный интерфейс.
- [x] Дождаться и проверить GitHub Actions Windows/macOS для corrective source commit `45320ee`.
- [x] Обновить release contract и создать annotated tag `v1.0.1` после полного локального gate.
- [x] Пересобрать consumer payload из `v1.0.1`, проверить и обновить remote `main` без force.

## Фаза P5 - [x] Public smoke и closeout

Цель: доказать реальный пользовательский путь и терминально закрыть выпуск.

Deliverable: fresh public clone/bootstrap evidence, retrospective, knowledge outcome и complete Plan v2.

Сделано, когда: публичный `main` устанавливается, финальные gates зеленые, plan/retro записаны в source и post-release commit отправлен.

Задачи:

- [x] Выполнить fresh clone `main` и URL-first bootstrap во временных каталогах.
- [x] Провести acceptance, impact и security review фактических remote refs/settings.
- [x] Создать retrospective и knowledge closeout.
- [x] Завершить plan, выполнить post-release source commit и push.

## Проверки

- Полный локальный pre-tag профиль - PASS: TemplateSource 152, analysis 86, agents 5, Plan lifecycle, canon/graph, Mastery, consumer boundary 185, bootstrap, distribution 14, knowledge self-test, privacy 37 и sanitizer Source.
- Hosted GitHub Actions run `33096366313` для corrective commit `45320ee` - Windows и macOS PASS.
- Hosted GitHub Actions run `33104745676` для release commit `52c736e` - Windows и macOS PASS.
- Remote refs/settings - PASS: `source` на `52c736e`, consumer `main` на `cd7b01a`, `v1.0.0` на `9441c78`, `v1.0.1` на `52c736e`, default `main`, template flag и About.
- Fresh public `main` - PASS: DistributionTemplate, sanitizer 185 и URL-first bootstrap в независимый `generated-project + initialized + report-only`, Git `main`, remotes 0.
- Final plan, knowledge, graph, privacy, structure, inventory и diff gates выполняются перед post-release source commit; failure блокирует push.

## Связанные решения

- Решения: [контракт source/consumer release](../TEMPLATE.md), [URL-first решение](../docs/decisions/2026-08-22-url-first-codex-install.md).

## Resume checkpoint

- Текущая фаза: нет - план завершен
- Уже выполнено: P4 завершена: v1.0.1 опубликован, consumer main пересобран, remote refs/settings подтверждены, Actions run33104745676 success на Windows и macOS; public clone и URL-first smoke PASS.
- Последние успешные проверки: PASS: run33104745676; remote refs/settings; public main DistributionTemplate и sanitizer185; GeneratedProject initialized report-only, branch main, remotes0; hosted run33096366313.
- Точные рабочие paths: plans/2026-08-23-github-release-v1-0-0.md; plans/INDEX.md; retrospectives/2026-08-28_11-20_github-release-v1-0-1.md; .template-manifest.json; TEMPLATE.md
- Git checkpoint: v1:53aa1ebe89a214beeaca02a19b99aa2b3a1d3fd795c19f8338dd74e7ec3232b1
- Следующее действие: нет - plan terminal; follow-up требует новый plan_id
- Блокеры: нет
- Обновлено: 2026-08-28T07:23:08Z

## Итог

- Реализовано целиком: публичный Codex Analyst Template, source/consumer release model, immutable `v1.0.0`, corrective `v1.0.1`, GitHub Template settings, URL-first установка, hosted Windows/macOS CI и fresh public smoke.
- Что осталось: только обычное сопровождение через новые Plan v2; в этом plan незакрытых release-действий нет.
- Коммиты: source release `52c736e`; consumer main `cd7b01a`; terminal plan и retrospective закрепляются post-release source closeout commit.

Перед `complete` закрой criteria и фазы, заполни проверки, итог, `result_refs`, closeout и финальный knowledge outcome. Не дублируй остальные machine fields в body.
