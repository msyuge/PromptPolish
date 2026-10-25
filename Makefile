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

# Реальная генерация на модели (первый запуск скачивает ≈1,7 ГБ). Отчёт: build/integration-output.txt
integration: generate
	set -o pipefail; TEST_RUNNER_PROMPTPOLISH_INTEGRATION=1 $(XCB) test -only-testing:PromptPolishTests/LLMIntegrationTests 2>&1 | grep -E "error:|passed|failed|skipped|TEST"; cat build/integration-output.txt

run: build
	-pkill -x PromptPolish
	open $(APP)

clean:
	rm -rf build $(PROJECT)
