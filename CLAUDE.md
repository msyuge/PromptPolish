# PromptPolish

Личная menu bar утилита для macOS: улучшает промт к AI-чату прямо в поле ввода любого приложения.
Пользователь выделяет текст → ⌥⌘P → локальная модель (MLX Swift) стримит улучшенную версию в плавающую панель → «Заменить».

## Решения (не менять без обсуждения)
- Полностью офлайн: модель встроена через MLX Swift (mlx-swift-examples / MLXLLM), без Ollama и сетевых API. Сеть нужна только один раз — скачать веса модели.
- macOS 14+, только Apple Silicon (arm64), Swift 5 language mode со `SWIFT_STRICT_CONCURRENCY=complete`.
- Без App Sandbox и без Hardened Runtime: нужен Accessibility (AXUIElement) и синтетические нажатия клавиш.
- `LSUIElement = YES` (нет иконки в Dock), UI — `MenuBarExtra`.
- Подпись: Debug — `Apple Development`, Release — `Developer ID Application` (team 6ALXRXJXN6), Manual, Hardened Runtime включён (entitlements не нужны). Bundle ID `com.alekseimaksimov.promptpolish`, версия 1.0.0. Стабильная подпись нужна, чтобы разрешение Accessibility не сбрасывалось после каждой пересборки.
- Распространение: DMG с Developer ID и нотаризацией (`make release`, `scripts/release.sh`, профиль notarytool `PromptPolish` в связке ключей создаёт пользователь). Mac App Store невозможен — нужен App Sandbox, а с ним нет Accessibility. Лицензии пакетов — `Resources/Acknowledgements.txt` (`scripts/make-acknowledgements.sh`), иконка — `scripts/make-icon.swift`.
- Проект генерируется XcodeGen из `project.yml`; `*.xcodeproj` в git не хранится.
- Инференс не блокирует main thread (actors, async/await).
- Пользовательский буфер обмена всегда восстанавливается (все типы, все элементы), в том числе при ошибках.
- LLM: `mlx-swift-lm` 3.x (MLXLLM/MLXLMCommon) + свои адаптеры к swift-huggingface (загрузчик) и swift-transformers (токенизатор), без макросов MLXHuggingFace (им нужно подтверждение доверия в Xcode). Выбор модели в меню и настройках (решение пользователя: только MLX, без Ollama/GGUF): `ModelLocator` сканирует MLX-модели в `~/.lmstudio/models`, `~/.cache/lm-studio/models` и кэше Hugging Face, `ModelCatalog` добавляет проверенные модели для скачивания с фильтром по памяти, `ModelStore` хранит выбор в UserDefaults и пересоздаёт `LLMEngine` при смене (старая модель выгружается, `Memory.clearCache()`). По умолчанию `mlx-community/Qwen3.5-4B-MLX-4bit` (у пользователя M2 с 8 ГБ, копия лежит в LM Studio); рассуждения Qwen отключены через `enable_thinking: false`.
- Системные инструкции (решение пользователя): у каждого чата своя — `Resources/SystemPrompts/SystemPrompt-<chat>.txt`; `generic` — инструкция пользователя «Prompt Engineer AI» дословно, остальные — её адаптации под рекомендации разработчика чата. Модель выдаёт промт в блоке кода; утилита вставляет только содержимое блока. Уточняющие вопросы модель начинает с «ВОПРОСЫ:», пользователь отвечает в панели.
- Защита от дефектов маленькой модели (`PromptQuality.swift`): `IdeaNormalizer` отрезает из идеи обращение к утилите («сделай промпт для…», кроме промптов для генераторов картинок/видео/музыки); `PromptQuality` находит мета-задачу, пересказ системной инструкции (совпадение ≥5 слов подряд, кроме фраз в «ёлочках» и слов из идеи) и сломанные XML-теги, до двух раз просит модель исправить, а оставшиеся дефектные строки вырезает. Каркасы в инструкциях — списком разделов с описаниями после тире, без образца в блоке кода.
- Системные инструкции редактируются во вкладке настроек «Системные инструкции» (`SystemPromptStore`, `SystemPromptsView`), отдельного пункта меню нет; все вкладки настроек одного размера (`SettingsView.size`): правки пользователя лежат в `~/Library/Application Support/PromptPolish/SystemPrompts/SystemPrompt-<chat>.txt` поверх стандартных из бандла; пустая или совпадающая со стандартной правка удаляется. Сессия фиксирует инструкции на момент начала.
- Этап 5 (решение пользователя): утилита сама определяет AI-чат (bundle ID приложения; в браузере — `AXURL` у `AXWebArea`) и берёт его системную инструкцию.

## Команды
```
make generate   # xcodegen → PromptPolish.xcodeproj
make build      # сборка Debug в build/DerivedData
make test       # unit-тесты (без интеграционных)
make integration # реальная генерация на модели, отчёт в build/integration-output.txt
make run        # сборка, перезапуск приложения (Debug)
make install    # Release в ~/Applications и запуск
make dmg        # подписанный DMG без нотаризации
make release    # DMG с Developer ID и нотаризацией (build/release)
make icon       # пересоздать иконку
make clean
```

## Структура
- `project.yml` — описание проекта (таргеты PromptPolish и PromptPolishTests).
- `PromptPolish/App` — точка входа, MenuBarExtra, `ImproveCoordinator` (весь сценарий).
- `PromptPolish/TextBridge` — чтение/замена текста: AXUIElement, fallback ⌘A/⌘C/⌘V, снимок буфера обмена.
- `PromptPolish/LLM` — `LLMEngine` (actor, MLX), `PromptBuilder`, очистка ответа, адаптеры Hugging Face.
- `PromptPolish/Chat` — `ChatTarget`: определение чата по bundle ID и URL страницы.
- `PromptPolish/Preview` — плавающая NSPanel превью и её размещение.
- `PromptPolish/Settings` — окно настроек: вкладки «Основные» и «Системные инструкции».
- `PromptPolish/Resources` — Info.plist (генерируется XcodeGen), `SystemPrompts/` (инструкции под каждый чат).
- `PromptPolishTests` — unit-тесты (хостятся в приложении).

## Окружение
- Ollama на машине установлена, но в MLX её модели (GGUF) не используются; второй движок через Ollama — идея для фазы 2.
- Для сборки MLX нужен Metal Toolchain: `xcodebuild -downloadComponent MetalToolchain` (уже установлен на этой машине).
- Первая сборка с MLX долгая (компиляция mlx и шейдеров) — запускать в фоне.

- Логи: `/usr/bin/log show --last 30m --predicate 'subsystem == "com.alekseimaksimov.promptpolish"' --info` — в zsh `log` перекрыт встроенной командой, нужен полный путь.

## Документация
- `README.md` (английский) и `README.ru.md` — обзор, установка, разрешения, модели, ограничения, сборка и релиз. Держать оба в синхроне.
- `docs/guide.md` и `docs/guide.ru.md` — пошаговая инструкция пользователя и решение проблем. Интерфейс приложения на русском: в английских текстах названия кнопок даются по-русски с переводом в скобках.
- Репозиторий: https://github.com/msyuge/PromptPolish (публичный, лицензия MIT). Релизы с DMG — GitHub Releases.
- `docs/phase2.md` — план фазы 2 (inline ghost-text подсказки) и прочие идеи.

## Ручные проверки
Агент не может выдать разрешение Accessibility и нажать глобальный хоткей — такие шаги проверяет пользователь.
