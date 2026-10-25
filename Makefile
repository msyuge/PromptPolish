PROJECT := PromptPolish.xcodeproj
SCHEME  := PromptPolish
DERIVED := build/DerivedData
APP     := $(DERIVED)/Build/Products/Debug/PromptPolish.app
XCB     := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED)

.PHONY: generate build test integration run clean

generate:
	xcodegen generate --quiet

build: generate
	$(XCB) build -quiet

test: generate
	$(XCB) test -quiet -skip-testing:PromptPolishTests/LLMIntegrationTests

# Реальная генерация на модели (первый запуск скачивает веса). Отчёт: build/integration-output.txt
# Другая модель: make integration MODEL=mlx-community/Qwen2.5-7B-Instruct-4bit
integration: generate
	set -o pipefail; TEST_RUNNER_PROMPTPOLISH_INTEGRATION=1 TEST_RUNNER_PROMPTPOLISH_MODEL=$(MODEL) $(XCB) test -only-testing:PromptPolishTests/LLMIntegrationTests 2>&1 | grep -E "error:|passed|failed|skipped|TEST"; cat build/integration-output.txt

run: build
	-pkill -x PromptPolish
	open $(APP)

clean:
	rm -rf build $(PROJECT)
