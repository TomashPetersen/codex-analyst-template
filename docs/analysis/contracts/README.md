# API и integration contract attachments

Эта папка хранит необязательные машиночитаемые JSON-вложения к каноническим `INT-*` из [`../models/`](../models/README.md). Attachment не получает отдельный ID и не становится вторым владельцем требований.

## Имена и ownership

- OpenAPI: `int-0001.openapi.json`.
- AsyncAPI: `int-0001.asyncapi.json`.
- Числовая часть exact совпадает с существующим `INT-0001`.
- Канонический INT ссылается на attachment через `related_refs` repository-root-relative путем.
- Один attachment принадлежит ровно одному INT. Orphan attachments запрещены.

## Содержимое

- JSON root является object.
- OpenAPI содержит непустое string-поле `openapi`.
- AsyncAPI содержит непустое string-поле `asyncapi`.
- Duplicate JSON keys запрещены. `$ref` остается local `#/...`; URL/URI/endpoint fields используют только relative value или безопасный HTTPS без credentials и signed query.
- Нормативный INT описывает producer, consumer, scope, operations/messages, ownership, versioning, auth mechanism, errors, idempotency, timeout/retry, compatibility, SLA, privacy и verification.
- Attachment содержит machine-readable schema и не дублирует prose без необходимости.

Production secrets, credentials, signed URLs и персональные данные запрещены. Конкретный OpenAPI/AsyncAPI linter выбирается вместе с версией стандарта и реальным контрактом; базовый gate проверяет ownership, limits, UTF-8, JSON, discriminator и safety.

Основной контракт: [`../../../analysis/CONTRACT.md`](../../../analysis/CONTRACT.md#api-и-integration-attachments).
