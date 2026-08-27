# История шаблона

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
