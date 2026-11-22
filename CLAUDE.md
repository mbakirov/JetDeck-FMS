# JetDeck FMS

Процедурный тренажёр Airbus A320-214 (CFM56-5B) для iPad 13". Пользователь управляет самолётом только через автоматику: FCU, MCDU, EFIS и рычаги. Ручного пилотирования нет. Приложение работает полностью на устройстве.

Описание продукта и эпики E01–E12 лежат в Notion:
- Обзор: https://app.notion.com/p/41f196379bdc806b939fd5a19b9feb49
- E01 Ядро и контракт: https://app.notion.com/p/41f196379bdc81f0bc98e90b6ce3da75

## Архитектура

- `SimCore/` — ядро симуляции. Пакет Swift без кода UI. Фиксированный шаг 20 мс (50 Гц).
- `App/` — приложение SwiftUI (появится в E12). В нём нет логики симуляции.

Приложение отправляет `InputEvent`, ядро возвращает `Snapshot`. Контракт: `SimCore/Sources/SimCoreContract/SimCoreContract.swift`. Фасад `SimEngine` имеет три операции: `send(event)`, `step()`, `latestSnapshot`.

Цели пакета:

| Цель | Назначение |
|---|---|
| `SimCoreContract` | Типы событий и снимка, запись полёта, JSON |
| `Kernel` | Шина состояния `SimState`, протокол `SimModule`, `StepContext` |
| `World`, `Sensors`, `FMS`, `AutoFlight`, `FBW`, `Aircraft`, `Warnings`, `Displays` | Модули симуляции. В E01 это заглушки |
| `SimCore` | Фасад `SimEngine`, внешний цикл `SimRunner`, повтор записи `Replayer` |
| `SnapshotDiff` | Сравнение снимков с допуском |
| `simcore-cli` | Команды `replay`, `diff`, `bench`, `gen-recording`, `golden-update` |
| `ARINC424` | Разбор записей FAA CIFP (ARINC 424-18). Только для сборки |
| `NavDBBuilder` | Конвертер CIFP в SQLite, проверка `verify`, замер `bench`. Только для сборки |
| `navdb-cli` | Команды `convert`, `verify`, `bench`, `manifest`, `extract-sample` |
| `NavDB` | Схема SQLite и модуль чтения `NavDatabaseReader` |
| `NavDBUpdate` | Загрузка новой базы: манифест, SHA-256, замена файла, выбор базы, уведомления |

Навигационная база описана в `Docs/navdb.md`. Протокол `NavDatabase` и типы данных лежат в `Kernel/NavData`. Модули симуляции видят только их, а не `NavDB`.

## Правила ядра

Эти правила нельзя нарушать.

- **Слои.** Модуль симуляции импортирует только `Kernel` и `SimCoreContract`. Модули не импортируют друг друга. Тип новой секции состояния добавляется в `Kernel`. SwiftPM не отклоняет лишний импорт, поэтому правило проверяет `make lint-imports`. При добавлении цели обновить `Package.swift` и `SimCore/Scripts/check-imports.sh`.
- **Один писатель.** Каждую секцию `SimState` пишет один модуль. Модуль получает свою секцию как `inout`, а всё состояние — только для чтения.
- **Порядок шага** фиксирован: ввод, World, Sensors, FMS, AutoFlight, FBW, Aircraft, Warnings, Displays, снимок. Он задан в `SimEngine.standardModules()`.
- **Детерминизм.** В ядре нет системных часов, `Date()` и случайных чисел без `context.seed`. Результат не зависит от порядка `Set` и `Dictionary`. Время симуляции равно `step × 0.02`, оно не накапливается сложением.
- **События.** Событие — это физическое действие на органе управления («ручку ALT вытянули»), а не намерение («включить OP CLB»). Событие, отправленное между шагами N и N+1, применяется в шаге N+1.
- **Снимок** содержит данные, готовые к показу, в единицах индикации (kt, ft, ft/min, градусы, NM). Внутреннего состояния в нём нет.
- **Множества в контракте** помечаются `@CanonicalSet`, чтобы JSON был одинаковым при каждом запуске.
- **Версия контракта.** Изменение формата событий или снимка требует увеличить `contractSchemaVersion` и пересоздать эталоны командой `make golden-update`. Запись с другой версией не воспроизводится.
- **Пауза и скорость** — функции внешнего цикла `SimRunner`. Ядро о них не знает.
- **Перезапуск сценария** — это новый экземпляр `SimEngine`, а не событие.
- **Навигационная база** передаётся в `SimEngine(initial:navData:)` и не меняется, пока существует ядро. Новая база — новый `SimEngine`. Запись полёта хранит идентичность базы, повтор с другой базой отклоняется.
- **Схема NavDB.** Изменение таблиц требует увеличить `NavDBSchema.version`. Изменение конвертера, которое меняет содержимое базы, требует увеличить `NavDBBuilder.version`.
- **Внешних зависимостей нет.** SQLite3 и CryptoKit — системные модули.

## Команды

Запускать из корня репозитория.

| Команда | Действие |
|---|---|
| `make build` | Собрать пакет |
| `make test` | Все тесты |
| `make test-<Цель>` | Тесты одной цели, например `make test-Kernel` |
| `make lint-imports` | Проверить правило слоёв |
| `make soak` | 30 000 шагов (10 минут времени симуляции) |
| `make replay-goldens` | Повторить эталонные записи и сравнить снимки |
| `make golden-update` | Пересоздать эталонные снимки после намеренного изменения |
| `make bench` | Замерить время шага, отчёт в `build/reports/` |
| `make build-ios` | Собрать библиотеки SimCore и NavDB под iPadOS (нужен Xcode) |
| `make check` | `build`, `lint-imports`, `test`, `bench`. Эту команду вызывает CI |
| `make navdb-cycle` | Загрузить CIFP цикла, конвертировать, проверить, замерить, записать манифест. `AIRAC=next` — следующий цикл. Нужна сеть |
| `make navdb-convert` | Конвертировать `build/cifp/<cycle>/FAACIFP18` в `build/navdb/navdb-<cycle>.sqlite` |
| `make navdb-verify` | Сравнить базу с исходным файлом CIFP |
| `make navdb-bench` | Замерить запрос для ND, ошибка при p99 больше `NAVDB_P99_MS` |
| `make navdb-sample` | Сделать новый тестовый фрагмент CIFP |

Перед завершением любой задачи выполнить `make check`.

## Тесты

- Swift Testing (`import Testing`). У каждой цели своя цель тестов.
- Эталоны: `SimCore/Tests/GoldenTests/Goldens/<имя>/recording.json` и `snapshots.jsonl`. Допуски сравнения задаются в `GoldenTests.swift`.
- Тесты NavDB используют фрагмент CIFP `SimCore/Tests/Fixtures/CIFP-sample-2611.txt` и строят базу во временном каталоге. Полный файл CIFP в репозитории не хранится.
- Запускать тесты через `make`. Makefile передаёт компилятору путь к плагину макросов Swift Testing. Без него сборка тестов иногда падает с ошибкой «plugin for module 'TestingMacros' not found».

## Платформы и язык

iPadOS 26, macOS 26. Swift 6 со строгой проверкой параллельности. Синхронизация — `Mutex` из `Synchronization`.

## Процесс

Работа идёт по эпикам из Notion. CI вызывает `make check`.
