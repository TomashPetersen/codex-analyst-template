---
artifact_kind: plan
plan_contract_version: 2
plan_id: PLAN-20260823-github-release-v1-0-0
task_key: github-release-v1-0-0
prompt_ref: prompts/plan-and-deliver.md
status: in-progress
current_phase: P4
updated_at: 2026-08-27T18:32:15Z
completed_at: null
closeout_status: pending
knowledge_outcome: null
candidate_ids: []
result_refs: []
affected_canon: []
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

## Фаза P4 - [WIP] GitHub publication и corrective release

Цель: опубликовать refs и repository settings без force или скрытого external write.

Deliverable: публичные `main`, `source`, неизменяемые `v1.0.0` и `v1.0.1`, default `main`, template flag и About.

Сделано, когда: remote refs и settings подтверждены независимо, а GitHub Actions source matrix зеленая.

Задачи:

- [x] Повторно подтвердить пустой remote и отправить consumer `main` первым.
- [x] Отправить source branch и immutable tag без force.
- [x] Настроить default branch, GitHub Template и About через авторизованный интерфейс.
- [x] Дождаться и проверить GitHub Actions Windows/macOS для corrective source commit `45320ee`.
- [ ] Обновить release contract и создать annotated tag `v1.0.1` после полного локального gate.
- [ ] Пересобрать consumer payload из `v1.0.1`, проверить и обновить remote `main` без force.

## Фаза P5 - [ ] Public smoke и closeout

Цель: доказать реальный пользовательский путь и терминально закрыть выпуск.

Deliverable: fresh public clone/bootstrap evidence, retrospective, knowledge outcome и complete Plan v2.

Сделано, когда: публичный `main` устанавливается, финальные gates зеленые, plan/retro записаны в source и post-release commit отправлен.

Задачи:

- [ ] Выполнить fresh clone `main` и URL-first bootstrap во временных каталогах.
- [ ] Провести acceptance, impact и security review фактических remote refs/settings.
- [ ] Создать retrospective и knowledge closeout.
- [ ] Завершить plan, выполнить post-release source commit и push.

## Проверки

## Связанные решения

- Решения: [контракт source/consumer release](../TEMPLATE.md), [URL-first решение](../docs/decisions/2026-08-22-url-first-codex-install.md).

## Resume checkpoint

- Текущая фаза: P4
- Уже выполнено: Release contract обновлен до v1.0.1 с immutable v1.0.0; полный локальный pre-tag профиль завершен зеленым.
- Последние успешные проверки: PASS: TemplateSource152; analysis86; agents5; Plan lifecycle; canon/graph; Mastery; consumer185; bootstrap; distribution14; knowledge self-test; privacy37; sanitizer Source; Plan v2; diff-check; hosted run33096366313 Windows/macOS success.
- Точные рабочие paths: .template-manifest.json; TEMPLATE-DISTRIBUTION.json; README.md; TEMPLATE.md; TEMPLATE-CHANGELOG.md; plans/2026-08-23-github-release-v1-0-0.md; plans/INDEX.md
- Git checkpoint: v1:b0555fe0f727e6db1c4314c4ce9c9194d2801c6824b883a0df84566813d5940b
- Следующее действие: Review exact release diff, commit source release contract, create annotated v1.0.1 и построить consumer payload из exact tag.
- Блокеры: нет
- Обновлено: 2026-08-27T18:32:15Z

## Итог

- Реализовано целиком:
- Что осталось:
- Коммиты:

Перед `complete` закрой criteria и фазы, заполни проверки, итог, `result_refs`, closeout и финальный knowledge outcome. Не дублируй остальные machine fields в body.
