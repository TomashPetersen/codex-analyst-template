---
artifact_kind: decision
status: accepted
knowledge_outcome: none
candidate_ids: []
affected_canon:
  - .template-manifest.json
  - AGENTS.md
  - CODEX-INSTALL-PROMPT.md
  - README.md
  - PROJECT.md
  - scripts/README.md
supersedes: []
blocked_reason: null
---

# Решение: URL-first установка через временный consumer clone

## Контекст и владелец

Публичный шаблон должен устанавливаться после одной понятной команды с URL GitHub repository. Обязательный предварительный `Use this template` создает лишний ручной шаг и не соответствует требуемому UX. Решение принято владельцем в рамках [follow-up plan](../../plans/2026-08-22-url-first-codex-install.md) до первого публичного release.

## Решение

- Основной пользовательский вход - короткая команда Codex установить шаблон по HTTPS URL и сначала прочитать repository instructions.
- Сообщение, содержащее только URL без цели, не считается надежной командой. GitHub About и начало README дают одну короткую формулировку с явным глаголом установки.
- Codex клонирует только consumer `main` во временный локальный каталог, проверяет URL, читает `README.md`, `AGENTS.md`, descriptor, install entrypoint и импортируемые local modules до исполнения.
- Canonical clone остается read-only источником. `scripts/new-project.ps1` копирует exact portable allowlist в отсутствующий destination, запускает independent initialization и создает отдельный Git `main` без remote.
- `new-project.ps1` становится portable и принимает два проверенных source modes: `template-source + source-placeholder` и `distribution-template + github-template`.
- In-place `initialize-project.ps1 -FromGitHubTemplate` продолжает отклонять clone canonical template. Этот режим предназначен только для нового repository, созданного пользователем через GitHub Template.
- Если writable target нельзя определить безопасно, Codex задает один объединенный вопрос. В остальных случаях используются нейтральные project defaults, которые позднее меняются через паспорт проекта.
- Clone и network orchestration остаются в agent prompt, а не в скачиваемом PowerShell entrypoint. Скрипты шаблона сами не обращаются к сети.

## Рассмотренные альтернативы

- Обязательный `Use this template` отклонен как лишний ручной шаг перед локальной установкой.
- Инициализация canonical clone на месте отклонена: проект наследовал бы `.git`, историю и remote шаблона, а пользователь мог бы случайно отправить изменения upstream.
- Download-and-run однострочного remote PowerShell script отклонен из-за скрытой сетевой загрузки и исполнения до локального аудита.
- Новый большой installer с дублированием copy/rollback logic отклонен в пользу расширения уже проверенного `new-project.ps1`.
- Молчаливая запись в произвольную пользовательскую папку отклонена. Агент использует текущий writable workspace или задает один вопрос.

## Последствия и риски

- Consumer payload увеличивается на один portable script, который остается безопасным в generated project и fail-closed отклоняет generated source mode.
- Полностью автономный путь зависит от доступности Git, PowerShell 7, сети и разрешений Codex. Системный approval на network/filesystem не обходится.
- GitHub не гарантирует, что один голый URL будет воспринят как команда, поэтому надежный минимальный интерфейс состоит из URL и одной короткой фразы.
- Temporary clone должен удаляться только по точному проверенному пути, созданному текущей установкой.

## Проверка

- Distribution fixture собирает consumer payload и запускает portable `new-project.ps1` из canonical-clone-like repository.
- Generated project обязан иметь уникальный project ID, `initialized + report-only`, независимый Git `main`, ноль remotes и отсутствие source-only paths.
- Tampered descriptor или payload, generated source, existing destination и in-place canonical initialization остаются заблокированы.
- Source/consumer sanitizer, boundary, bootstrap, Plan v2 и structure gates остаются обязательными.

## Откат или замена

До release изменения можно точечно вернуть в manifest, scripts, tests и public docs. После публикации несовместимое изменение install contract получает новый Plan v2, ADR и SemVer release; опубликованный tag не переписывается.

## Связи

- План: [URL-first установка](../../plans/2026-08-22-url-first-codex-install.md).
- Source release contract: [TEMPLATE.md](../../TEMPLATE.md).
- Пользовательская установка: [CODEX-INSTALL-PROMPT.md](../../CODEX-INSTALL-PROMPT.md).
- Обратные ссылки на примененные candidates: нет.
