---
artifact_kind: retrospective
knowledge_outcome: none
candidate_ids: []
affected_canon:
  - .agents/skills/project-delivery/SKILL.md
  - .codex/config.toml
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

# Ретроспектива: Codex Analyst Template v1.1.0

## Задача и связи

Выпуск выполнен по [Plan v2 активного обучения и release 1.1.0](../plans/2026-08-31-active-learning-v1-1-release.md). Публичный результат находится в [Codex Analyst Template](https://github.com/TomashPetersen/codex-analyst-template), а зеленая hosted matrix зафиксирована в [GitHub Actions run 33428255350](https://github.com/TomashPetersen/codex-analyst-template/actions/runs/33428255350).

## Что сделано

- Delivery preflight теперь выбирает intent и максимум один допустимый Local Mastery method, а Plan v2 сохраняет и проверяет этот выбор при resume.
- Knowledge graph оставлен вторичным маршрутом только для bounded cross-domain discovery, impact, traceability, backlinks, conflicts и duplicate search.
- README получил короткие copy-ready prompts для URL-first установки и первого рабочего цикла после установки.
- В portable config добавлен один optional namespaced Context7 MCP с ограниченным allowlist без token, headers или runtime dependency.
- Trusted builder собирает consumer из detached snapshot exact tag commit, игнорирует replacement refs и выполняет final provenance attestation до atomic publish.
- Source опубликован на commit `26afe81`, annotated tag `v1.1.0` указывает на этот commit, consumer `main` обновлен обычным descendant-коммитом `ee2844a` без force.

## Что проверено и какими командами

- Полный локальный pre-tag профиль, skill validators, privacy, sanitizer, Plan, knowledge, analysis, agents, mastery, consumer, bootstrap и cross-platform fixtures - PASS.
- Distribution security harness - PASS, 17 сценариев; независимые security review и red-team не нашли blockers.
- Первый hosted run `33419990968`: macOS PASS за 57 минут, Windows отменен только лимитом job 60 минут после 1 часа. Timeout увеличен до 90 минут без изменения gates.
- GitHub Actions run `33428255350` для source commit `26afe81` - completed successfully на полной Windows/macOS matrix.
- Remote refs подтверждены независимо: `source` на `26afe81`, peeled `v1.1.0` на `26afe81`, consumer `main` на `ee2844a`.
- Fresh public `main`: DistributionTemplate и Consumer sanitizer PASS; URL-first bootstrap создал `generated-project + initialized + report-only`, Git `main`, remotes 0, commits 0.

## Что не получилось или осталось

- Исходный hosted run не уложился в 60 минут на Windows. Тесты не сокращались и не отключались; исправлен только job timeout, после чего полный rerun прошел.
- GitHub Release object, packages, settings и deploy не создавались, так как они не входят в release scope.
- После terminal closeout дальнейшие изменения требуют нового Plan v2.

## Как было и как стало

До выпуска Local Mastery policy существовала без обязательного retrieval и сохраняемой traceability в delivery plan, а graph route был недостаточно ограничен. После выпуска выбор метода проверяем, переживает resume, graph не подменяет owner artifacts, а пользователь может скопировать с GitHub короткий prompt установки и отдельный prompt работы с локальным пространством.

## Что выучено

- Hosted timeout должен иметь запас относительно измеренной cross-platform matrix и не должен использоваться как способ сократить проверки.
- Release payload должен подтверждать provenance после всех staging writers, а не только сразу после копирования tag.
- Отдельный knowledge candidate не нужен: устойчивые изменения уже закреплены в skill, Plan contract, routes, builder, tests и release documentation; capture mode template source остается `disabled`.

## Security review

- Персональные данные: не добавлялись; privacy и sanitizer gates зеленые.
- Контент третьих лиц: исходный код или документы не импортировались; Context7 представлен только optional endpoint contract и отражен в notices.
- Внешние отправки: ограничены разрешенными `source`, annotated tag `v1.1.0` и consumer `main`; force и изменение GitHub settings не применялись.
- Секреты: значения credentials не читались и не записывались; template не содержит token, headers или credential URL.
