---
artifact_kind: plan
plan_contract_version: 2
plan_id: PLAN-20260831-context7-config-layer-recovery
task_key: context7-config-layer-recovery
prompt_ref: prompts/plan-and-deliver.md
status: complete
current_phase: null
updated_at: 2026-08-31T05:38:31Z
completed_at: 2026-08-31T05:38:31Z
closeout_status: complete
knowledge_outcome: none
candidate_ids: []
result_refs:
  - .codex/config.toml
  - docs/decisions/2026-08-30-context7-mcp-template.md
  - scripts/verify-codex-agents.ps1
  - retrospectives/2026-08-31_09-25_context7-config-layer-recovery.md
affected_canon:
  - .codex/config.toml
  - .template-manifest.json
  - AGENTS.md
  - README.md
  - TEMPLATE-CHANGELOG.md
  - docs/decisions/2026-08-30-context7-mcp-template.md
  - scripts/test-analyst-consumer-boundary.ps1
  - scripts/test-cross-platform-bootstrap.ps1
  - scripts/test-github-template-distribution.ps1
  - scripts/verify-codex-agents.ps1
blocked_reason: null
---

# План: Восстановление загрузки проекта при конфликте Context7 config layers

## Цель

Устранить отказ загрузки задач проекта «Аналитик», вызванный слиянием одноименных global и project MCP tables с разными transport, и сохранить переносимый optional remote Context7 через уникальный project-scoped server ID.

## Границы

Входит:

- заменить generic project server ID `context7` на namespaced `codex_analyst_context7`;
- синхронизировать exact portable config, deterministic verifiers, consumer/distribution fixtures и текущую документацию решения;
- добавить regression, запрещающий возврат generic `[mcp_servers.context7]` в portable config;
- проверить загрузку обеих существующих задач, сохранность истории и project-wide gates.

Не входит:

- изменение user-level Codex config;
- удаление или переписывание истории задач;
- изменение endpoint, allowlist, auth, secrets, runtime dependency или обязательности Context7;
- commit, push, tag, release, deploy или изменение GitHub.

## Критерии приемки

1. Обе задачи проекта «Аналитик» открываются без config error и имеют loadable status, а их сохраненная история доступна полностью.
2. Portable `.codex/config.toml` содержит ровно один `[mcp_servers.codex_analyst_context7]` с текущими `url`, `enabled`, `required` и `enabled_tools`, без `command`, `args`, credentials или headers.
3. Common global `[mcp_servers.context7]` больше не объединяется с project table; repair не записывает user-level config, а параллельная app-managed delta отделена от MCP repair и проверена безопасным byte audit.
4. Verifier и все supported consumer/distribution paths требуют namespaced ID и отклоняют generic project ID как regression.
5. Focused и project-wide offline gates проходят; независимый review не находит material defects.
6. Все исходные незакоммиченные изменения вне repair scope сохранены, external write и release actions не выполняются.

## Риски, безопасность и откат

- Новый ID может показать второй Context7 рядом с уже настроенным global Context7, но transport tables больше не смешиваются и загрузка проекта не блокируется.
- Static portable config не может знать effective user/system layers, поэтому collision regression проверяет common generic ID и фиксирует namespaced contract.
- Внешний endpoint, server instructions и outputs остаются недоверенными данными; секреты не добавляются.
- Откат выполняется точечной заменой namespaced stanza на last-known-good agents-only config либо восстановлением сохраненной резервной копии; global config не затрагивается.

## Фаза P1 - [x] Контракт инцидента и regression

Цель: закрепить доказанную причину, решение и воспроизводимую защиту от повторения.

Deliverable: заполненный Plan v2, namespaced contract и negative fixture для generic ID.

Сделано, когда: scope ограничен project files, альтернативы оценены, а focused verifier различает safe и conflicting config.

Задачи:

- [x] Зафиксировать global STDIO + project HTTP collision одного server ID и сохранность задач.
- [x] Обосновать namespaced ID против изменения global config и удаления portable capability.
- [x] Добавить exact positive config и negative generic-ID regression.

## Фаза P2 - [x] Синхронизация portable contract

Цель: обновить все текущие владельцы exact server ID без изменения исторического complete plan.

Deliverable: согласованные config, policy, ADR, changelog и distribution harnesses.

Сделано, когда: все обязательные occurrences используют `codex_analyst_context7`, а adversarial исторические fixtures сохранены намеренно.

Задачи:

- [x] Обновить `.codex/config.toml`, `AGENTS.md`, `README.md`, ADR и changelog.
- [x] Обновить четыре deterministic PowerShell harnesses.
- [x] Сохранить terminal plan 2026-08-30 и adversarial intent fixtures без переписывания истории.

## Фаза P3 - [x] Проверка, review и closeout

Цель: доказать загрузку проекта, переносимость и отсутствие регрессий.

Deliverable: зеленые focused/project-wide gates, loadable tasks, independent review и terminal checkpoint.

Сделано, когда: criteria закрыты evidence, knowledge closeout выполнен, plan terminal, commit/push не выполнены.

Задачи:

- [x] Запустить focused config/self-tests и consumer/distribution gates.
- [x] Запустить plans, knowledge и structure gates.
- [x] Провести независимый review и security/impact audit.
- [x] Повторно открыть обе задачи, сохранить итог и закрыть plan.

## Проверки

- `pwsh -NoProfile -File ./scripts/verify-codex-agents.ps1 -SelfTest`
- `pwsh -NoProfile -File ./scripts/test-analyst-consumer-boundary.ps1`
- `pwsh -NoProfile -File ./scripts/test-cross-platform-bootstrap.ps1`
- `pwsh -NoProfile -File ./scripts/test-github-template-distribution.ps1`
- `pwsh -NoProfile -File ./scripts/verify-plans.ps1`
- `pwsh -NoProfile -File ./scripts/verify-knowledge.ps1`
- `pwsh -NoProfile -File ./scripts/verify-structure.ps1 -Mode TemplateSource`
- Codex app status/read checks для обеих задач проекта.
- Итог: agents SelfTest 26 PASS; consumer boundary portable=186 PASS; cross-platform bootstrap PASS; distribution 15 PASS; analysis SelfTest 115 PASS; IT semantics 107 PASS; plans, knowledge, sanitizer, structure 160 и `git diff --check` PASS; две независимые проверки не нашли material defects.

## Связанные решения

- Решения: follow-up к completed `PLAN-20260830-context7-mcp-template`; official OpenAI config layers объединяют user и trusted project settings, а `command` и `url` принадлежат разным MCP transport.
- Отклонено изменение global config: оно расширяет scope и может повредить другие проекты.
- Отклонено удаление portable Context7: оно отменяет прямо выбранную capability шаблона.
- Выбрано namespaced project ID: сохраняет capability и разрывает доказанный key collision минимальной contract delta.
- Параллельная запись root key `service_tier` в user-level config не откатывалась: in-memory удаление только этой 26-byte строки точно восстановило audit baseline SHA-256, а `mcp_servers.context7` не изменился.

## Resume checkpoint

- Текущая фаза: нет - план завершен
- Уже выполнено: P1-P3 закрыты; обе task histories сохранены и снова idle; namespaced contract, generic-ID regression, ADR и retrospective завершены; knowledge-curator outcome none.
- Последние успешные проверки: agents 26; consumer portable=186; cross-platform; distribution 15; analysis 115; IT semantics 107; plans; knowledge; sanitizer; structure 160; diff check; independent review и red-team audit PASS.
- Точные рабочие paths: .codex/config.toml; AGENTS.md; README.md; TEMPLATE-CHANGELOG.md; .template-manifest.json; docs/decisions/2026-08-30-context7-mcp-template.md; scripts/verify-codex-agents.ps1; scripts/test-analyst-consumer-boundary.ps1; scripts/test-cross-platform-bootstrap.ps1; scripts/test-github-template-distribution.ps1; retrospectives/2026-08-31_09-25_context7-config-layer-recovery.md; plans/2026-08-31-context7-config-layer-recovery.md.
- Git checkpoint: v1:1a34c604927c4e94d4b78ff784bf179505bed2d8067d3cece4abea75c144e3d1
- Следующее действие: нет - plan terminal; follow-up требует новый plan_id
- Блокеры: нет
- Обновлено: 2026-08-31T05:38:31Z

## Итог

- Реализовано целиком: восстановлена загрузка двух задач, transport collision устранен namespaced server ID, portable Context7 сохранен, regression и historical closeout добавлены.
- Что осталось: в scope этого plan ничего; второй optional Context7 ID и возможные будущие profile/system layer collisions остаются известными ограничениями, а не блокерами.
- Коммиты: не выполнялись.

Перед `complete` закрой criteria и фазы, заполни проверки, итог, `result_refs`, closeout и финальный knowledge outcome. Не дублируй остальные machine fields в body.
