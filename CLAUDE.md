# PromptPolish

Личная menu bar утилита для macOS: улучшает промт к AI-чату прямо в поле ввода любого приложения.
Пользователь выделяет текст → ⌥⌘P → локальная модель (MLX Swift) стримит улучшенную версию в плавающую панель → «Заменить».

## Решения (не менять без обсуждения)
- Полностью офлайн: модель встроена через MLX Swift (mlx-swift-examples / MLXLLM), без Ollama и сетевых API. Сеть нужна только один раз — скачать веса модели.
- macOS 14+, только Apple Silicon (arm64), Swift 5 language mode со `SWIFT_STRICT_CONCURRENCY=complete`.
- Без App Sandbox и без Hardened Runtime: нужен Accessibility (AXUIElement) и синтетические нажатия клавиш.
- `LSUIElement = YES` (нет иконки в Dock), UI — `MenuBarExtra`.
- Подпись: `Apple Development` (team 6ALXRXJXN6), Manual. Стабильная подпись нужна, чтобы разрешение Accessibility не сбрасывалось после каждой пересборки.
- Проект генерируется XcodeGen из `project.yml`; `*.xcodeproj` в git не хранится.
- Инференс не блокирует main thread (actors, async/await).
- Пользовательский буфер обмена всегда восстанавливается (все типы, все элементы), в том числе при ошибках.
- LLM: `mlx-swift-lm` 3.x (MLXLLM/MLXLMCommon) + свои адаптеры к swift-huggingface (загрузчик) и swift-transformers (токенизатор), без макросов MLXHuggingFace (им нужно подтверждение доверия в Xcode). Модель по умолчанию `mlx-community/Qwen2.5-3B-Instruct-4bit`, кэш — стандартный `~/.cache/huggingface/hub`; полный снимок из кэша грузится без сети.
- Системный промт — `PromptPolish/Resources/SystemPrompt.txt`: простые инструкции на английском под маленькую модель, промт пользователя оборачивается в `<prompt>…</prompt>`.
- Этап 5 (решение пользователя): утилита сама определяет, в каком AI-чате находится (bundle ID десктопного приложения; для браузеров — `AXURL` у `AXWebArea`), и готовит промт под этот чат (короткие подсказки о формате поверх общего системного промта).

## Команды
```
make generate   # xcodegen → PromptPolish.xcodeproj
make build      # сборка Debug в build/DerivedData
make test       # unit-тесты (без интеграционных)
make integration # реальная генерация на модели, отчёт в build/integration-output.txt
make run        # сборка, перезапуск приложения
make clean
```

## Структура
- `project.yml` — описание проекта (таргеты PromptPolish и PromptPolishTests).
- `PromptPolish/App` — точка входа, MenuBarExtra.
- `PromptPolish/Resources` — Info.plist (генерируется XcodeGen из `project.yml`), ресурсы.
- `PromptPolishTests` — unit-тесты (хостятся в приложении).

## Окружение
- Для сборки MLX нужен Metal Toolchain: `xcodebuild -downloadComponent MetalToolchain` (уже установлен на этой машине).
- Первая сборка с MLX долгая (компиляция mlx и шейдеров) — запускать в фоне.

## Ручные проверки
Агент не может выдать разрешение Accessibility и нажать глобальный хоткей — такие шаги проверяет пользователь.
