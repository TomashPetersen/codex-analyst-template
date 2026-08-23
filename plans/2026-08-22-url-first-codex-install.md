---
artifact_kind: plan
plan_contract_version: 2
plan_id: PLAN-20260822-url-first-codex-install
task_key: url-first-codex-install
prompt_ref: prompts/plan-and-deliver.md
status: complete
current_phase: null
updated_at: 2026-08-22T10:58:58Z
completed_at: 2026-08-22T10:58:58Z
closeout_status: complete
knowledge_outcome: none
candidate_ids: []
result_refs:
  - README.md
  - CODEX-INSTALL-PROMPT.md
  - scripts/new-project.ps1
  - scripts/test-analyst-consumer-boundary.ps1
  - docs/decisions/2026-08-22-url-first-codex-install.md
  - retrospectives/2026-08-22_14-55_url-first-codex-install.md
affected_canon:
  - .template-manifest.json
  - AGENTS.md
  - CODEX-INSTALL-PROMPT.md
  - PROJECT.md
  - README.md
  - scripts/README.md
  - TEMPLATE.md
blocked_reason: null
---

# План: URL-first установка Codex Analyst Template

## Цель

Сделать основным пользовательским маршрутом установку по URL: пользователь передает Codex ссылку публичного GitHub repository и одну короткую команду, после чего Codex самостоятельно читает инструкции, безопасно клонирует consumer `main`, создает независимый локальный проект, инициализирует его и запускает проверки.

## Границы

Входит:

- URL-first onboarding без обязательного предварительного `Use this template`;
- короткий copy-paste prompt для GitHub About/README и полный fallback prompt;
- безопасное создание независимого проекта из клона canonical distribution template;
- сохранение существующего GitHub Template маршрута как дополнительного;
- regression test для distribution clone -> generated project;
- обновление portable manifest, публичных инструкций и release contract.

Не входит:

- автоматическое создание GitHub repository пользователя;
- commit, tag, push, публикация или изменение GitHub settings;
- установка Codex, Git или PowerShell;
- настройка MCP, plugins, connectors, models или secrets;
- обещание, что сообщение, содержащее только URL без глагола установки, всегда будет трактоваться агентом как команда.

## Критерии приемки

1. В начале README есть однострочная команда: установить шаблон по указанному URL, прочитать README и выполнить URL-first contract.
2. Пользователю не требуется заранее нажимать `Use this template`, редактировать набор placeholders или вручную запускать PowerShell.
3. Codex может задать максимум один объединенный вопрос только если невозможно безопасно определить writable target; остальные метаданные имеют нейтральные defaults.
4. Clone canonical consumer `main` не инициализируется in-place и не сохраняет template remote в созданном проекте.
5. `new-project.ps1` принимает проверенный `template-source` или `distribution-template`, копирует exact portable payload и создает независимый `generated-project + initialized + report-only`.
6. Direct clone canonical template по-прежнему отклоняется старым `-FromGitHubTemplate`; GitHub Template repository пользователя остается поддержанным дополнительным путем.
7. URL-first fixture доказывает distribution clone -> independent generated project, отсутствие source-only paths, новый Git `main`, отсутствие remote и зеленые GeneratedProject gates.
8. Source/consumer sanitizer, manifest, bootstrap, distribution, Plan v2 и structure gates проходят без ослабления trust boundaries.

## Риски, безопасность и откат

- URL является недоверенным вводом: prompt разрешает только публичный HTTPS GitHub repository без credentials, signed query и redirects на иной host.
- Клонированные scripts считаются недоверенными до чтения README, AGENTS, descriptor, entrypoint и импортируемых local modules.
- Canonical clone используется только как временный read-only источник; финальный project создается атомарно в отсутствующем destination и получает независимый Git без remote.
- Удаляется только созданный агентом точный temporary clone после успешной установки или безопасной ошибки.
- Existing in-place initializer и GitHub Template route сохраняются для обратной совместимости; откат возможен точечным возвратом измененных docs/scripts/tests до release.

## Фаза P1 - [x] Контракт URL-first установки

Цель: согласовать единственный безопасный путь от URL в чате до локального generated project.

Deliverable: documented flow, decision record и testable acceptance map.

Сделано, когда: выбран reuse `new-project.ps1`, определены defaults, trust gates и fallback.

Задачи:

- [x] Зафиксировать рекомендуемый flow и отклоненные альтернативы.
- [x] Определить минимальный prompt и поведение при неясном target.
- [x] Привязать каждый критерий к коду или fixture.

## Фаза P2 - [x] Distribution clone bootstrap

Цель: разрешить `new-project.ps1` создавать независимый проект из проверенного consumer payload.

Deliverable: новые fail-closed mode branches в `new-project.ps1` и `initialize-project.ps1`.

Сделано, когда: оба source modes проходят, generated project не наследует template `.git` или remote, in-place canonical clone остается запрещен.

Задачи:

- [x] Добавить точное определение `source-placeholder` и `github-template` descriptor.
- [x] Добавить independent-Git initialization из distribution copy.
- [x] Сохранить rollback, exact inventory и reparse/path gates.

## Фаза P3 - [x] README, prompt и GitHub About

Цель: сделать URL-first маршрут очевидным человеку и однозначным для Codex.

Deliverable: обновленные README, install prompt, AGENTS, PROJECT, INDEX, scripts docs и release metadata.

Сделано, когда: один короткий prompt находится в начале README и готов для GitHub About, а полный prompt не требует ручного `Use this template`.

Задачи:

- [x] Сделать URL-first основным маршрутом, GitHub Template - дополнительным.
- [x] Зафиксировать neutral defaults и максимум один вопрос о target.
- [x] Обновить consumer manifest и source-only release contract.

## Фаза P4 - [x] Regression и приемка

Цель: доказать end-to-end путь без реального network/push.

Deliverable: distribution fixture и полный локальный gate report.

Сделано, когда: synthetic URL-first clone проходит independent bootstrap, privacy, boundary и structure gates.

Задачи:

- [x] Добавить позитивные и негативные fixtures нового режима.
- [x] Выполнить AST, focused tests, distribution roundtrip и полный structure gate.
- [x] Проверить impact и security boundary.

## Фаза P5 - [x] Review и closeout

Цель: завершить follow-up без release-действий.

Deliverable: review evidence, retrospective, knowledge outcome и terminal Plan v2.

Сделано, когда: findings закрыты, итог зафиксирован, plan имеет status complete.

Задачи:

- [x] Сопоставить фактический diff с acceptance criteria.
- [x] Выполнить knowledge closeout и финальные gates.
- [x] Завершить plan без commit, tag или push.

## Проверки

- PowerShell AST: 37 файлов, PASS.
- URL-first consumer boundary: portable payload 185 файлов, independent Git `main`, zero remote, source-only absent, PASS.
- GitHub distribution roundtrip: 14 checks, PASS.
- Cross-platform bootstrap: source copy, GitHub Template initialization, defaults и invalid input, PASS.
- Analysis self-test: 86 scenarios, PASS; текущий canon и runs имеют zero issues.
- Codex agents self-test: 5 scenarios, PASS; пять read-only roles и cap 3.
- Mastery harness: 24/24, PASS; knowledge privacy harness: 37 bounded checks, PASS.
- Plan v2, canon, knowledge, три производных индекса и A02 control plane: PASS.
- Source sanitization: 208 файлов, PASS; TemplateSource structure: 151 canonical Markdown-файл, PASS.
- Release boundary: HEAD, tags, remotes, staged changes, commit, push и external write отсутствуют.

## Связанные решения

- Решения: follow-up уточняет install UX до первого публичного release; существующий release boundary остается неизменным.

## Resume checkpoint

- Текущая фаза: нет - план завершен
- Уже выполнено: P1-P5 deliverables завершены; acceptance review без findings; retrospective создана; knowledge outcome none; release boundary сохранена.
- Последние успешные проверки: PASS: AST 37; analysis 86; agents 5; mastery 24; privacy 37; distribution 14; sanitizer 208; structure 151 canonical Markdown.
- Точные рабочие paths: README.md; CODEX-INSTALL-PROMPT.md; scripts/new-project.ps1; scripts/initialize-project.ps1; docs/decisions/2026-08-22-url-first-codex-install.md; retrospectives/2026-08-22_14-55_url-first-codex-install.md; plans/2026-08-22-url-first-codex-install.md
- Git checkpoint: v1:ef5a5c21dfec844fc0b17f452ec14d171c81393fe5a7476572116211680537f2
- Следующее действие: нет - plan terminal; follow-up требует новый plan_id
- Блокеры: нет
- Обновлено: 2026-08-22T10:58:58Z

## Итог

- Реализовано целиком: основной URL-first install UX, автономный agent contract, portable bootstrap из distribution clone, нейтральные defaults, fail-closed trust gates, дополнительный GitHub Template путь, документация и regression fixtures.
- Что осталось: только отдельно разрешенные release-действия - создать историю Git, подготовить ветки `source` и `main`, tag `v1.0.0`, push, GitHub Template setting и GitHub About.
- Коммиты: отсутствуют; этот follow-up не выполнял stage, commit, tag или push.

Перед `complete` закрой criteria и фазы, заполни проверки, итог, `result_refs`, closeout и финальный knowledge outcome. Не дублируй остальные machine fields в body.
