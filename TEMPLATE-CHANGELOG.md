# История шаблона

## 1.1.0 - 2026-08-31

- Delivery-задачи теперь до предметной работы выбирают intent, проверяют Local Mastery и сохраняют максимум один active, непросроченный и применимый method в проверяемом разделе Plan v2.
- Корневые routes используют knowledge graph только для bounded cross-domain discovery, impact, traceability, backlinks, conflicts и duplicate search, после чего ведут к точным owner artifacts.
- README содержит два коротких copy-ready промта: URL-first установка с GitHub и начало работы в локальном пространстве через Codex.
- Deployable consumer получает единственный optional remote Context7 MCP с namespaced server ID `codex_analyst_context7`, exact official URL и tool allowlist, без credentials, `npx`, Node.js dependency или обязательного per-run вызова; namespaced ID предотвращает mixed-transport collision с распространенным user-level `context7`, а offline gates отклоняют generic project ID, другие MCP и configuration drift.
- Усилен единый `it-analysis`: Business Analysis, Requirements Engineering, process/decision semantics, NFR и solution architecture используют проверяемые методы и сохраняют authority boundaries.
- IBM Solution Architect оригинально переоперационализирован как profile `solution-architecture` для существующего `system_analyst` только при `intent_id: architecture`; новые роли и IBM output files не добавлялись.
- Добавлены `requirements-verification`, `requirements-prioritization`, `solution-evaluation` и architecture routing с одним primary и максимум одним supplementary method.
- Восьмифайловый run и canonical body contracts разделяют requirements verification, stakeholder validation и approval, а `REV-*` использует machine-readable `review_record`.
- Добавлены deterministic verifier rules и source-only offline semantic-contract fixtures без model, network или MCP calls.
- Trusted builder материализует exact detached snapshot source tag, игнорирует Git replacement refs и перед atomic publish повторно подтверждает provenance каждого portable файла.
- Template и mastery bundle подготовлены как `1.1.0`; distribution consumer этой версии собирается только из проверенного source tag `v1.1.0`.

## 1.0.1 - 2026-08-27

- Нормализованы physical system temp roots для hosted macOS fixtures без ослабления reparse-point gates.
- Reparse fixtures semantic knowledge gate используют Junction на Windows и SymbolicLink на macOS.
- Полная GitHub Actions matrix подтверждена на Windows и macOS до корректирующего tag.
- `v1.0.0` сохранен неизменным; consumer `main` пересобирается только из tagged source `v1.0.1`.

## 1.0.0 - 2026-08-20

- Создан публично-безопасный Codex Analyst Template для системного и бизнес-анализа.
- Добавлены formal-analysis, восьмифайловый run, OpenAPI/AsyncAPI attachments, Mermaid, terminal run gates и 86-scenario self-test.
- Добавлены пять project-scoped read-only ролей с лимитом трех одновременно работающих специалистов и single-writer synthesis.
- Добавлены четыре project-local skills и prompts для bounded run, программы анализа, review и разрешенного handoff.
- Analyst Mastery включен в immutable baseline, registry расширен всеми 18 closed analysis intents.
- Knowledge graph включает approved formal-analysis artifacts и исключает plans, runs, RAW и retrospectives.
- Добавлены sanitize gate, consumer-boundary test, Windows bootstrap и macOS CI contract.
- Основным onboarding стал URL-first маршрут: Codex клонирует consumer `main` во временный каталог и создает независимый локальный проект через portable `new-project.ps1`; `Use this template` остается дополнительным путем.
- Подготовлена release-модель source/main/v1.0.0 без выполнения commit, tag, push или публикации.
