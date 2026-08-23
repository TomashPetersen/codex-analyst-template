# Бизнес - каноническая карта

Эта зона хранит подтвержденную бизнес-модель одного продукта. Продуктовые знания находятся в [`product/`](../product/INDEX.md), гипотезы - в [`idea/`](../idea/INDEX.md), а необработанные материалы - только в [`inbox/raw/`](../inbox/raw/README.md).

Формальные stakeholders, capabilities, процессы, правила и бизнес-требования имеют отдельного владельца в [`analysis/`](analysis/INDEX.md). Они проверяются `verify-analysis.ps1` и не смешиваются с общим canon contract файлов ниже.

- [`overview.md`](overview.md) - ценностное предложение, участники и границы.
- [`architecture.md`](architecture.md) - роли, capabilities и потоки ценности.
- [`model-and-economics.md`](model-and-economics.md) - доход, затраты, unit economics и допущения.
- [`go-to-market.md`](go-to-market.md) - позиционирование, каналы и путь к ценности.
- [`goals-and-metrics.md`](goals-and-metrics.md) - цели, определения метрик и критерии решений.
- [`assets/README.md`](assets/README.md) - разрешенные бренд- и доказательные материалы.
- [`analysis/INDEX.md`](analysis/INDEX.md) - формальный бизнес-анализ с ID `STK`, `CAP`, `BP`, `RULE` и `BR`.

Каждый canon-файл имеет status `template`, `active` или `deprecated`; graph индексирует только `active`. Для внешнего факта указывай safe `source_refs` и дату проверки. При конфликте обновляй один owner artifact через candidate и authority, а не создавай конкурирующую версию.
