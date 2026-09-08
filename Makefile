SHELL := /bin/sh
.DEFAULT_GOAL := help

VERSION := 1.1.0
TAG := v$(VERSION)
# Do not build signed bundles inside a cloud-synchronized source tree: Finder
# metadata can be attached after signing.  Release output remains explicit and
# can be overridden for a controlled build host.
BUILD ?= /private/tmp/arc-build-$(VERSION)
OUTPUT ?= /private/tmp/arc-output-$(VERSION)
HOST_ARCH := $(shell /usr/bin/uname -m)
DEV_SCRATCH := $(BUILD)/swift-development
DEV_BIN := $(DEV_SCRATCH)/$(HOST_ARCH)-apple-macosx/debug
APP_DEV_SCRATCH := $(BUILD)/swift-app-development
APP_DEV_BIN := $(APP_DEV_SCRATCH)/$(HOST_ARCH)-apple-macosx/debug
ARC_DEV := $(DEV_BIN)/arc-dev
ARC_CLI := $(DEV_BIN)/arc
COMMAND_TEST_DIR := $(BUILD)/command-test
KNOWLEDGE_DIR := $(BUILD)/knowledge
KNOWLEDGE_CONTAINER := $(KNOWLEDGE_DIR)/ARC_AI.arc-kb
KNOWLEDGE_SHA := $(KNOWLEDGE_DIR)/ARC_AI.sha256
TERSE_SPEC := languages/terse/001-terse-language-specification.txt
DEVELOPMENT_APP := $(BUILD)/development/ARC.app
ARM_SCRATCH := $(BUILD)/swift-arm64
ARM_BIN := $(ARM_SCRATCH)/arm64-apple-macosx/release
RELEASE_APP := $(BUILD)/release/ARC.app
CANDIDATE_DIR := $(OUTPUT)/candidate/ARC-$(VERSION)
FINAL_DIR := $(OUTPUT)/release/ARC-$(VERSION)
CANDIDATE_DMG := $(CANDIDATE_DIR)/ARC-$(VERSION).dmg
CANDIDATE_LITERATURE := $(CANDIDATE_DIR)/ARC_AI_Relay_Chat_Literature.pdf
CANDIDATE_SOURCE := $(CANDIDATE_DIR)/ARC-$(VERSION)-source.tar.gz
CANDIDATE_MANIFEST := $(CANDIDATE_DIR)/ARC-$(VERSION)-MANIFEST.json
DVT_REPORT ?=
LITERATURE_PDF ?=

.PHONY: help build test command-test release-contract-test source-check source-archive-test \
	knowledge knowledge-test check \
	app-development app-development-check app-release app-release-check \
	release-environment release-prepare release-dvt release-prepared-check \
	release-prepare-guard release-seal clean

help:
	@echo "ARC 1.0 native build"
	@echo ""
	@echo "  make check                  Build and run all local checks"
	@echo "  make app-development        Build a host-architecture ARC.app"
	@echo "  make app-release            Build an unsigned Apple silicon ARC.app"
	@echo "  make release-prepare        Sign, notarize, and freeze a candidate"
	@echo "  make release-dvt DVT_REPORT=/absolute/report.txt"
	@echo "  make release-seal DVT_REPORT=/absolute/report.txt"
	@echo "  make clean                  Remove generated build and release output"
	@echo ""
	@echo "Release targets require SIGNING_IDENTITY and NOTARY_PROFILE."

build:
	/usr/bin/xcrun swift build --scratch-path "$(DEV_SCRATCH)" --product ARCDesktop
	/usr/bin/xcrun swift build --scratch-path "$(DEV_SCRATCH)" --product arc
	/usr/bin/xcrun swift build --scratch-path "$(DEV_SCRATCH)" --product arc-dev

test: build
	/usr/bin/xcrun swift test --scratch-path "$(DEV_SCRATCH)"
	@/bin/mkdir -p "$(BUILD)/c-tests"
	@/bin/rm -f -- "$(BUILD)/c-tests/ARC_AI-required.arc-kb"
	"$(ARC_DEV)" knowledge-build --source "$(CURDIR)" \
		--output "$(BUILD)/c-tests/ARC_AI-required.arc-kb"
	/usr/bin/xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -pedantic \
		-I knowledge/include knowledge/src/arc_knowledge.c \
		knowledge/tests/knowledge_api_test.c -o "$(BUILD)/c-tests/knowledge-api-test"
	@digest=`/usr/bin/shasum -a 256 "$(BUILD)/c-tests/ARC_AI-required.arc-kb" | \
		/usr/bin/awk '{print $$1}'`; \
		"$(BUILD)/c-tests/knowledge-api-test" \
			"$(BUILD)/c-tests/ARC_AI-required.arc-kb" "$$digest"

command-test: build
	@/bin/rm -rf -- "$(COMMAND_TEST_DIR)"
	@/bin/mkdir -p "$(COMMAND_TEST_DIR)/root"
	@"$(ARC_CLI)" version > "$(COMMAND_TEST_DIR)/actual" \
		2> "$(COMMAND_TEST_DIR)/error"
	@/usr/bin/printf 'ARC 1.1.0\n' > "$(COMMAND_TEST_DIR)/expected"
	@/usr/bin/cmp "$(COMMAND_TEST_DIR)/expected" "$(COMMAND_TEST_DIR)/actual"
	@test ! -s "$(COMMAND_TEST_DIR)/error"
	@/bin/mkdir -p "$(COMMAND_TEST_DIR)/root/current/specifications" \
		"$(COMMAND_TEST_DIR)/root/current/legal"
	@/usr/bin/install -m 644 "$(KNOWLEDGE_CONTAINER)" \
		"$(COMMAND_TEST_DIR)/root/current/ARC_AI.arc-kb"
	@/usr/bin/install -m 644 "$(KNOWLEDGE_SHA)" \
		"$(COMMAND_TEST_DIR)/root/current/ARC_AI.sha256"
	@for file in 10_specs/platform_support/*.txt; do \
		/usr/bin/install -m 644 "$$file" \
			"$(COMMAND_TEST_DIR)/root/current/specifications/`/usr/bin/basename "$$file"`" || exit $$?; \
	done
	@/usr/bin/install -m 644 LICENSE "$(COMMAND_TEST_DIR)/root/current/legal/LICENSE"
	@/usr/bin/install -m 644 NOTICE.md "$(COMMAND_TEST_DIR)/root/current/legal/NOTICE.md"
	@/bin/mkdir -p "$(COMMAND_TEST_DIR)/root/current/languages/terse"
	@/usr/bin/install -m 644 "$(TERSE_SPEC)" "$(COMMAND_TEST_DIR)/root/current/$(TERSE_SPEC)"
	@/usr/bin/shasum -a 256 "$(TERSE_SPEC)" | /usr/bin/awk '{print $$1}' > "$(COMMAND_TEST_DIR)/root/current/languages/terse/TERSE.sha256"
	@status=0; "$(ARC_CLI)" --root "$(COMMAND_TEST_DIR)/root" poll \
		--room room-000000000000 --id ai-000000000000 \
		--binding 00000000-0000-4000-8000-000000000000 \
		> "$(COMMAND_TEST_DIR)/actual" 2> "$(COMMAND_TEST_DIR)/error" || status=$$?; \
		test "$$status" -eq 2
	@/usr/bin/printf '%s\n' \
		'{"error":{"code":"NOT_FOUND","message":"ARC could not find that room.","retryable":false},"ok":false}' \
		> "$(COMMAND_TEST_DIR)/expected"
	@/usr/bin/cmp "$(COMMAND_TEST_DIR)/expected" "$(COMMAND_TEST_DIR)/actual"
	@test ! -s "$(COMMAND_TEST_DIR)/error"
	@status=0; "$(ARC_CLI)" --root "$(COMMAND_TEST_DIR)/root" act \
		--room room-000000000000 --id ai-000000000000 \
		--binding 00000000-0000-4000-8000-000000000000 \
		--operation 00000000-0000-4000-8000-000000000000 \
		--request '{"text":"x","to":"ai-000000000000","type":"message"}' \
		> "$(COMMAND_TEST_DIR)/actual" 2> "$(COMMAND_TEST_DIR)/error" || status=$$?; \
		test "$$status" -eq 2
	@/usr/bin/cmp "$(COMMAND_TEST_DIR)/expected" "$(COMMAND_TEST_DIR)/actual"
	@test ! -s "$(COMMAND_TEST_DIR)/error"
	@status=0; "$(ARC_CLI)" --root "$(COMMAND_TEST_DIR)/root" doctor --room bad --json \
		> "$(COMMAND_TEST_DIR)/actual" 2> "$(COMMAND_TEST_DIR)/error" || status=$$?; \
		test "$$status" -eq 2
	@/usr/bin/printf '%s\n' \
		'{"ok":true,"result":{"context":[{"label":"Room ID","value":"bad"}],"failure":{"check":"PATH","message":"The Room ID is invalid.","next_action":"Return to the room list."},"valid":false}}' \
		> "$(COMMAND_TEST_DIR)/expected"
	@/usr/bin/cmp "$(COMMAND_TEST_DIR)/expected" "$(COMMAND_TEST_DIR)/actual"
	@test ! -s "$(COMMAND_TEST_DIR)/error"
	@request=`/usr/bin/printf '\377'`; \
		status=0; "$(ARC_CLI)" --root "$(COMMAND_TEST_DIR)/root" act \
			--room room-000000000000 --id ai-000000000000 \
			--binding 00000000-0000-4000-8000-000000000000 \
			--operation 00000000-0000-4000-8000-000000000000 \
			--request "$$request" > "$(COMMAND_TEST_DIR)/actual" \
			2> "$(COMMAND_TEST_DIR)/error" || status=$$?; test "$$status" -eq 2
	@/usr/bin/printf '%s\n' \
		'{"error":{"code":"INVALID_ARGUMENT","message":"Command-line arguments must be valid UTF-8.","retryable":false},"ok":false}' \
		> "$(COMMAND_TEST_DIR)/expected"
	@/usr/bin/cmp "$(COMMAND_TEST_DIR)/expected" "$(COMMAND_TEST_DIR)/actual"
	@test ! -s "$(COMMAND_TEST_DIR)/error"
	@status=0; "$(ARC_CLI)" unknown > "$(COMMAND_TEST_DIR)/actual" \
		2> "$(COMMAND_TEST_DIR)/error" || status=$$?; test "$$status" -eq 2
	@/usr/bin/printf '%s\n' \
		'Usage: arc version | help | spec list | spec read ID | guide | poll | act | doctor' \
		> "$(COMMAND_TEST_DIR)/expected"
	@/usr/bin/cmp "$(COMMAND_TEST_DIR)/expected" "$(COMMAND_TEST_DIR)/actual"
	@test ! -s "$(COMMAND_TEST_DIR)/error"
	@status=0; "$(ARC_CLI)" spec read 013 > "$(COMMAND_TEST_DIR)/actual" \
		2> "$(COMMAND_TEST_DIR)/error" || status=$$?; test "$$status" -eq 2
	@/usr/bin/printf '%s\n' 'ARC has no specification with that ID.' \
		> "$(COMMAND_TEST_DIR)/expected"
	@/usr/bin/cmp "$(COMMAND_TEST_DIR)/expected" "$(COMMAND_TEST_DIR)/actual"
	@test ! -s "$(COMMAND_TEST_DIR)/error"

source-check: build
	"$(ARC_DEV)" source-check --source "$(CURDIR)"

source-archive-test:
	@set -eu; \
		set -o pipefail; \
		toplevel=`/usr/bin/git rev-parse --show-toplevel 2>/dev/null` || { \
			/usr/bin/printf '%s\n' \
				'source-archive-test: fail closed: not a Git checkout' >&2; \
			exit 1; \
		}; \
		test "$$toplevel" = "$(CURDIR)" || { \
			/usr/bin/printf '%s\n' \
				'source-archive-test: fail closed: Git toplevel is not this source tree' >&2; \
			exit 1; \
		}; \
		tmp=`/usr/bin/mktemp -d "/private/tmp/arc-source-archive.XXXXXX"`; \
		trap '/bin/rm -rf -- "$$tmp"' EXIT HUP INT TERM; \
		/usr/bin/git -c tar.umask=022 archive --format=tar \
			--prefix="ARC-$(VERSION)/" HEAD | /usr/bin/gzip -n > "$$tmp/source.tar.gz"; \
		/usr/bin/tar -tzvf "$$tmp/source.tar.gz" | \
			/usr/bin/awk 'substr($$1, 6, 1) == "w" || substr($$1, 9, 1) == "w" { exit 1 }'

knowledge: build
	@/bin/mkdir -p "$(KNOWLEDGE_DIR)"
	@/bin/rm -f -- "$(KNOWLEDGE_CONTAINER).stage" "$(KNOWLEDGE_SHA).stage"
	"$(ARC_DEV)" knowledge-build --source "$(CURDIR)" \
		--output "$(KNOWLEDGE_CONTAINER).stage" --release-notes
	@/usr/bin/shasum -a 256 "$(KNOWLEDGE_CONTAINER).stage" | \
		/usr/bin/awk '{print $$1}' > "$(KNOWLEDGE_SHA).stage"
	@/bin/chmod 644 "$(KNOWLEDGE_CONTAINER).stage" "$(KNOWLEDGE_SHA).stage"
	@/bin/mv -f "$(KNOWLEDGE_CONTAINER).stage" "$(KNOWLEDGE_CONTAINER)"
	@/bin/mv -f "$(KNOWLEDGE_SHA).stage" "$(KNOWLEDGE_SHA)"

knowledge-test: knowledge
	"$(ARC_DEV)" knowledge-validate --container "$(KNOWLEDGE_CONTAINER)"
	@tmp=`/usr/bin/mktemp -d "/private/tmp/arc-knowledge.XXXXXX"`; \
		trap '/bin/rm -rf -- "$$tmp"' EXIT HUP INT TERM; \
		"$(ARC_DEV)" knowledge-deconstruct --container "$(KNOWLEDGE_CONTAINER)" \
			--destination "$$tmp/text"; \
		"$(ARC_DEV)" knowledge-reconstruct --source "$$tmp/text" \
			--output "$$tmp/rebuilt.arc-kb"; \
		/usr/bin/cmp "$(KNOWLEDGE_CONTAINER)" "$$tmp/rebuilt.arc-kb"

release-contract-test: build
	@tmp=$$(/usr/bin/mktemp -d "/private/tmp/arc-release-contract.XXXXXX"); \
		trap '/bin/rm -rf -- "$$tmp"' EXIT HUP INT TERM; \
		/usr/bin/printf 'review dmg\n' > "$$tmp/ARC-$(VERSION).dmg"; \
		/usr/bin/printf '%%PDF-1.4 review literature\n%%%%EOF\n' \
			> "$$tmp/ARC_AI_Relay_Chat_Literature.pdf"; \
		/usr/bin/printf 'review source\n' > "$$tmp/ARC-$(VERSION)-source.tar.gz"; \
		"$(ARC_DEV)" candidate-manifest --version "$(VERSION)" --tag "$(TAG)" \
			--revision "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
			--dmg "$$tmp/ARC-$(VERSION).dmg" \
			--literature "$$tmp/ARC_AI_Relay_Chat_Literature.pdf" \
			--source "$$tmp/ARC-$(VERSION)-source.tar.gz" \
			--knowledge-sha256 \
			"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" \
			--output "$$tmp/ARC-$(VERSION)-MANIFEST.json" >/dev/null; \
		dmg=$$(/usr/bin/shasum -a 256 "$$tmp/ARC-$(VERSION).dmg" | \
			/usr/bin/awk '{print $$1}'); \
		source=$$(/usr/bin/shasum -a 256 "$$tmp/ARC-$(VERSION)-source.tar.gz" | \
			/usr/bin/awk '{print $$1}'); \
		literature=$$(/usr/bin/shasum -a 256 \
			"$$tmp/ARC_AI_Relay_Chat_Literature.pdf" | /usr/bin/awk '{print $$1}'); \
		manifest=$$(/usr/bin/shasum -a 256 "$$tmp/ARC-$(VERSION)-MANIFEST.json" | \
			/usr/bin/awk '{print $$1}'); \
		{ \
			/usr/bin/printf '%s\n' \
				'ARC 1.0 EXTERNAL DVT REPORT' \
				'schema: arc.dvt/1' \
				'version: $(VERSION)' \
				'tag: $(TAG)' \
				'revision: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
				"candidate_manifest_sha256: $$manifest" \
				'tester: Independent Test Engineer, Example Lab' \
				'independence: No ARC implementation role.' \
				'started_at: 2026-08-17T14:00:00.000Z' \
				'finished_at: 2026-08-17T15:00:00.000Z' \
				'machines: arm64=Example Mac' \
				'systems: arm64=macOS 15 build A' \
				'toolchains: arm64=Xcode A Swift A' \
				"prepared_hashes: dmg=$$dmg | source=$$source | literature=$$literature | manifest=$$manifest" \
				'deviations: No deviations.' \
				'decision: PASS' \
				'checks:'; \
			for test in DVT-001-SOURCE DVT-002-NATIVE-BUILD DVT-003-INSTALL \
				DVT-004-FIRST-ROOM DVT-005-TWO-AI-ACTIVE \
				DVT-006-QUALIFICATION-FAILURE DVT-007-PRODUCER-CHANGE \
				DVT-008-REPLACE-AND-RETIRE DVT-009-MESSAGES-AND-WORK \
				DVT-010-POLLING-RECOVERY DVT-011-ROOM-INTEGRITY \
				DVT-012-PRIVACY-AND-OFFLINE DVT-013-ACCESSIBILITY \
				DVT-014-AGE-14-USABILITY DVT-015-SIGNING-NOTARIZATION; do \
				/usr/bin/printf 'test: %s | PASS | exact synthetic parser evidence\n' \
					"$$test"; \
			done; \
			/usr/bin/printf '%s\n' 'end: arc.dvt/1'; \
		} > "$$tmp/report.txt"; \
		"$(ARC_DEV)" dvt-check --report "$$tmp/report.txt" \
			--candidate-manifest "$$tmp/ARC-$(VERSION)-MANIFEST.json" >/dev/null; \
		/usr/bin/sed 's/deviations: No deviations./deviations: unresolved/' \
			"$$tmp/report.txt" > "$$tmp/invalid.txt"; \
		status=0; "$(ARC_DEV)" dvt-check --report "$$tmp/invalid.txt" \
			--candidate-manifest "$$tmp/ARC-$(VERSION)-MANIFEST.json" \
			>/dev/null 2>/dev/null || status=$$?; \
		test "$$status" -ne 0; \
		/bin/mkdir -p "$$tmp/final"; \
		/usr/bin/install -m 644 "$$tmp/ARC-$(VERSION).dmg" \
		"$$tmp/final/ARC-$(VERSION).dmg"; \
		/usr/bin/install -m 644 "$$tmp/ARC-$(VERSION)-source.tar.gz" \
			"$$tmp/final/ARC-$(VERSION)-source.tar.gz"; \
		/usr/bin/install -m 644 "$$tmp/ARC_AI_Relay_Chat_Literature.pdf" \
			"$$tmp/final/ARC_AI_Relay_Chat_Literature.pdf"; \
		/usr/bin/install -m 644 "$$tmp/ARC-$(VERSION)-MANIFEST.json" \
			"$$tmp/final/ARC-$(VERSION)-MANIFEST.json"; \
		/usr/bin/install -m 644 "$$tmp/report.txt" \
			"$$tmp/final/ARC-$(VERSION)-DVT-REPORT.txt"; \
		"$(ARC_DEV)" release-metadata \
			--candidate-manifest "$$tmp/final/ARC-$(VERSION)-MANIFEST.json" \
			--dvt-report "$$tmp/final/ARC-$(VERSION)-DVT-REPORT.txt" \
			--signing-identity "Developer ID Application: Example" \
			--app-notarization-id "11111111-1111-4111-8111-111111111111" \
			--dmg-notarization-id "22222222-2222-4222-8222-222222222222" \
			--output "$$tmp/final/RELEASE-METADATA.json" >/dev/null; \
		"$(ARC_DEV)" checksums --directory "$$tmp/final" --version "$(VERSION)" \
			--output "$$tmp/final/SHA256SUMS" >/dev/null; \
		"$(ARC_DEV)" release-check --directory "$$tmp/final" \
			--version "$(VERSION)" >/dev/null; \
		/bin/mkdir -p "$$tmp/frozen"; \
		/usr/bin/printf 'keep this candidate\n' > "$$tmp/frozen/sentinel"; \
		status=0; $(MAKE) --no-print-directory release-prepare-guard \
			CANDIDATE_DIR="$$tmp/frozen" >/dev/null 2>/dev/null || status=$$?; \
		test "$$status" -ne 0; \
		/usr/bin/printf 'keep this candidate\n' | \
			/usr/bin/cmp - "$$tmp/frozen/sentinel"

check: source-check source-archive-test knowledge-test test command-test release-contract-test \
	app-development-check

app-development: knowledge
	/usr/bin/xcrun swift build --scratch-path "$(APP_DEV_SCRATCH)" \
		--product ARCDesktop -Xswiftc -DARC_VISUAL_TESTING
	@/bin/rm -rf -- "$(DEVELOPMENT_APP).stage" "$(DEVELOPMENT_APP)"
	@/bin/mkdir -p "$(DEVELOPMENT_APP).stage/Contents/MacOS" \
		"$(DEVELOPMENT_APP).stage/Contents/Resources/install/bin" \
		"$(DEVELOPMENT_APP).stage/Contents/Resources/install/current/specifications" \
		"$(DEVELOPMENT_APP).stage/Contents/Resources/install/current/legal"
	/usr/bin/install -m 755 "$(APP_DEV_BIN)/ARCDesktop" \
		"$(DEVELOPMENT_APP).stage/Contents/MacOS/ARC"
	/usr/bin/install -m 755 "$(DEV_BIN)/arc" \
		"$(DEVELOPMENT_APP).stage/Contents/Resources/install/bin/arc"
	/usr/bin/install -m 644 app/Info.plist "$(DEVELOPMENT_APP).stage/Contents/Info.plist"
	/usr/bin/install -m 644 app/Assets/ARC.icns \
		"$(DEVELOPMENT_APP).stage/Contents/Resources/ARC.icns"
	/usr/bin/install -m 644 app/Sources/ARCApp/PrivacyInfo.xcprivacy \
		"$(DEVELOPMENT_APP).stage/Contents/Resources/PrivacyInfo.xcprivacy"
	/usr/bin/install -m 644 "$(KNOWLEDGE_CONTAINER)" \
		"$(DEVELOPMENT_APP).stage/Contents/Resources/install/current/ARC_AI.arc-kb"
	/usr/bin/install -m 644 "$(KNOWLEDGE_SHA)" \
		"$(DEVELOPMENT_APP).stage/Contents/Resources/install/current/ARC_AI.sha256"
	@for file in 10_specs/platform_support/*.txt; do \
		/usr/bin/install -m 644 "$$file" \
			"$(DEVELOPMENT_APP).stage/Contents/Resources/install/current/specifications/`/usr/bin/basename "$$file"`" || exit $$?; \
	done
	/usr/bin/install -m 644 LICENSE \
		"$(DEVELOPMENT_APP).stage/Contents/Resources/install/current/legal/LICENSE"
	/usr/bin/install -m 644 NOTICE.md \
		"$(DEVELOPMENT_APP).stage/Contents/Resources/install/current/legal/NOTICE.md"
	@/bin/mkdir -p "$(DEVELOPMENT_APP).stage/Contents/Resources/install/current/languages/terse"
	/usr/bin/install -m 644 "$(TERSE_SPEC)" "$(DEVELOPMENT_APP).stage/Contents/Resources/install/current/$(TERSE_SPEC)"
	@/usr/bin/shasum -a 256 "$(TERSE_SPEC)" | /usr/bin/awk '{print $$1}' > "$(DEVELOPMENT_APP).stage/Contents/Resources/install/current/languages/terse/TERSE.sha256"
	@digest=`/bin/cat "$(KNOWLEDGE_SHA)"`; \
		"$(ARC_DEV)" install-manifest \
			--contents "$(DEVELOPMENT_APP).stage/Contents" --version "$(VERSION)" \
			--knowledge-sha256 "$$digest" \
			--output "$(DEVELOPMENT_APP).stage/Contents/Resources/install/ARC-INSTALL-MANIFEST.json"
	@/usr/bin/xattr -cr "$(DEVELOPMENT_APP).stage"
	/usr/bin/codesign --force --sign - --timestamp=none "$(DEVELOPMENT_APP).stage"
	@/bin/mv "$(DEVELOPMENT_APP).stage" "$(DEVELOPMENT_APP)"
	@/usr/bin/xattr -cr "$(DEVELOPMENT_APP)"
	/usr/bin/codesign --force --sign - --timestamp=none "$(DEVELOPMENT_APP)"

app-development-check: app-development
	"$(ARC_DEV)" app-check --app "$(DEVELOPMENT_APP)" --version "$(VERSION)"
	/usr/bin/codesign --verify --deep --strict "$(DEVELOPMENT_APP)"

app-release: knowledge
	/usr/bin/xcrun swift build -c release --arch arm64 \
		--scratch-path "$(ARM_SCRATCH)" --product ARCDesktop
	/usr/bin/xcrun swift build -c release --arch arm64 \
		--scratch-path "$(ARM_SCRATCH)" --product arc
	@/bin/rm -rf -- "$(RELEASE_APP).stage" "$(RELEASE_APP)"
	@/bin/mkdir -p "$(RELEASE_APP).stage/Contents/MacOS" \
		"$(RELEASE_APP).stage/Contents/Resources/install/bin" \
		"$(RELEASE_APP).stage/Contents/Resources/install/current/specifications" \
		"$(RELEASE_APP).stage/Contents/Resources/install/current/legal"
	/usr/bin/install -m 755 "$(ARM_BIN)/ARCDesktop" \
		"$(RELEASE_APP).stage/Contents/MacOS/ARC"
	/usr/bin/install -m 755 "$(ARM_BIN)/arc" \
		"$(RELEASE_APP).stage/Contents/Resources/install/bin/arc"
	@/bin/chmod 755 "$(RELEASE_APP).stage/Contents/MacOS/ARC" \
		"$(RELEASE_APP).stage/Contents/Resources/install/bin/arc"
	/usr/bin/install -m 644 app/Info.plist "$(RELEASE_APP).stage/Contents/Info.plist"
	/usr/bin/install -m 644 app/Assets/ARC.icns \
		"$(RELEASE_APP).stage/Contents/Resources/ARC.icns"
	/usr/bin/install -m 644 app/Sources/ARCApp/PrivacyInfo.xcprivacy \
		"$(RELEASE_APP).stage/Contents/Resources/PrivacyInfo.xcprivacy"
	/usr/bin/install -m 644 "$(KNOWLEDGE_CONTAINER)" \
		"$(RELEASE_APP).stage/Contents/Resources/install/current/ARC_AI.arc-kb"
	/usr/bin/install -m 644 "$(KNOWLEDGE_SHA)" \
		"$(RELEASE_APP).stage/Contents/Resources/install/current/ARC_AI.sha256"
	@for file in 10_specs/platform_support/*.txt; do \
		/usr/bin/install -m 644 "$$file" \
			"$(RELEASE_APP).stage/Contents/Resources/install/current/specifications/`/usr/bin/basename "$$file"`" || exit $$?; \
	done
	/usr/bin/install -m 644 LICENSE \
		"$(RELEASE_APP).stage/Contents/Resources/install/current/legal/LICENSE"
	/usr/bin/install -m 644 NOTICE.md \
		"$(RELEASE_APP).stage/Contents/Resources/install/current/legal/NOTICE.md"
	@/bin/mkdir -p "$(RELEASE_APP).stage/Contents/Resources/install/current/languages/terse"
	/usr/bin/install -m 644 "$(TERSE_SPEC)" "$(RELEASE_APP).stage/Contents/Resources/install/current/$(TERSE_SPEC)"
	@/usr/bin/shasum -a 256 "$(TERSE_SPEC)" | /usr/bin/awk '{print $$1}' > "$(RELEASE_APP).stage/Contents/Resources/install/current/languages/terse/TERSE.sha256"
	@digest=`/bin/cat "$(KNOWLEDGE_SHA)"`; \
		"$(ARC_DEV)" install-manifest \
			--contents "$(RELEASE_APP).stage/Contents" --version "$(VERSION)" \
			--knowledge-sha256 "$$digest" \
			--output "$(RELEASE_APP).stage/Contents/Resources/install/ARC-INSTALL-MANIFEST.json"
	@/bin/mv "$(RELEASE_APP).stage" "$(RELEASE_APP)"
	@/usr/bin/xattr -cr "$(RELEASE_APP)"

app-release-check: app-release
	"$(ARC_DEV)" app-check --app "$(RELEASE_APP)" --version "$(VERSION)" --release
	@test "`/usr/bin/lipo -archs "$(RELEASE_APP)/Contents/MacOS/ARC"`" = arm64
	@test "`/usr/bin/lipo -archs \
		"$(RELEASE_APP)/Contents/Resources/install/bin/arc"`" = arm64

release-environment:
	@test -n "$(SIGNING_IDENTITY)" || { echo "SIGNING_IDENTITY is required" >&2; exit 2; }
	@test -n "$(NOTARY_PROFILE)" || { echo "NOTARY_PROFILE is required" >&2; exit 2; }
	@test -n "$(LITERATURE_PDF)" || { echo "LITERATURE_PDF is required" >&2; exit 2; }
	@case "$(LITERATURE_PDF)" in /*) ;; *) echo "LITERATURE_PDF must be absolute" >&2; exit 2;; esac
	@test -f "$(LITERATURE_PDF)" || { echo "LITERATURE_PDF is not a file" >&2; exit 2; }
	@test "`/usr/bin/git rev-parse --verify HEAD`" = \
		"`/usr/bin/git rev-list -n 1 "$(TAG)"`" || { echo "HEAD is not $(TAG)" >&2; exit 2; }
	@test "`/usr/bin/git cat-file -t "refs/tags/$(TAG)"`" = tag || \
		{ echo "$(TAG) is not an annotated tag" >&2; exit 2; }
	/usr/bin/git diff --quiet
	/usr/bin/git diff --cached --quiet
	@test -z "`/usr/bin/git status --porcelain --untracked-files=all`" || \
		{ echo "release checkout is not clean" >&2; exit 2; }
	/usr/bin/xcrun --find swift >/dev/null
	/usr/bin/xcrun --find clang >/dev/null
	/usr/bin/xcrun --find notarytool >/dev/null
	/usr/bin/xcrun --find stapler >/dev/null

release-prepare-guard:
	@test ! -e "$(CANDIDATE_DIR)" || { \
		echo "candidate already frozen; remove it explicitly" >&2; exit 2; \
	}

release-prepare: release-environment check app-release-check
	@$(MAKE) --no-print-directory release-prepare-guard
	@/bin/rm -rf -- "$(CANDIDATE_DIR).stage"
	@/bin/mkdir -p "$(CANDIDATE_DIR).stage" "$(BUILD)/notary" "$(BUILD)/dmg-root"
	/usr/bin/codesign --force --options runtime --timestamp \
		--sign "$(SIGNING_IDENTITY)" "$(RELEASE_APP)/Contents/Resources/install/bin/arc"
	@/bin/rm -f -- "$(RELEASE_APP)/Contents/Resources/install/ARC-INSTALL-MANIFEST.json"
	@digest=`/bin/cat "$(KNOWLEDGE_SHA)"`; \
		"$(ARC_DEV)" install-manifest --contents "$(RELEASE_APP)/Contents" \
			--version "$(VERSION)" --knowledge-sha256 "$$digest" \
			--output "$(RELEASE_APP)/Contents/Resources/install/ARC-INSTALL-MANIFEST.json"
	@/usr/bin/xattr -cr "$(RELEASE_APP)"
	/usr/bin/codesign --force --options runtime --timestamp \
		--sign "$(SIGNING_IDENTITY)" "$(RELEASE_APP)"
	"$(ARC_DEV)" app-check --app "$(RELEASE_APP)" --version "$(VERSION)" --release
	/usr/bin/codesign --verify --deep --strict --verbose=2 "$(RELEASE_APP)"
	@/bin/rm -f -- "$(BUILD)/notary/ARC.zip" "$(BUILD)/notary/app.json" \
		"$(BUILD)/notary/dmg.json"
	/usr/bin/ditto -c -k --keepParent "$(RELEASE_APP)" "$(BUILD)/notary/ARC.zip"
	/usr/bin/xcrun notarytool submit "$(BUILD)/notary/ARC.zip" --wait \
		--keychain-profile "$(NOTARY_PROFILE)" --output-format json \
		> "$(BUILD)/notary/app.json"
	@test "`/usr/bin/plutil -extract status raw -o - "$(BUILD)/notary/app.json"`" = Accepted
	/usr/bin/xcrun stapler staple "$(RELEASE_APP)"
	/usr/bin/xcrun stapler validate "$(RELEASE_APP)"
	@/bin/rm -rf -- "$(BUILD)/dmg-root"
	@/bin/mkdir -p "$(BUILD)/dmg-root"
	/usr/bin/ditto "$(RELEASE_APP)" "$(BUILD)/dmg-root/ARC.app"
	@/bin/ln -s /Applications "$(BUILD)/dmg-root/Applications"
	/usr/bin/hdiutil create -quiet -fs HFS+ -volname "ARC $(VERSION)" \
		-srcfolder "$(BUILD)/dmg-root" "$(CANDIDATE_DIR).stage/ARC-$(VERSION).dmg"
	/usr/bin/codesign --force --timestamp --sign "$(SIGNING_IDENTITY)" \
		"$(CANDIDATE_DIR).stage/ARC-$(VERSION).dmg"
	/usr/bin/xcrun notarytool submit "$(CANDIDATE_DIR).stage/ARC-$(VERSION).dmg" --wait \
		--keychain-profile "$(NOTARY_PROFILE)" --output-format json \
		> "$(BUILD)/notary/dmg.json"
	@test "`/usr/bin/plutil -extract status raw -o - "$(BUILD)/notary/dmg.json"`" = Accepted
	/usr/bin/xcrun stapler staple "$(CANDIDATE_DIR).stage/ARC-$(VERSION).dmg"
	/usr/bin/xcrun stapler validate "$(CANDIDATE_DIR).stage/ARC-$(VERSION).dmg"
	@/usr/bin/git -c tar.umask=022 archive --format=tar --prefix="ARC-$(VERSION)/" "$(TAG)" | \
		/usr/bin/gzip -n > "$(CANDIDATE_DIR).stage/ARC-$(VERSION)-source.tar.gz"
	/usr/bin/install -m 644 "$(LITERATURE_PDF)" \
		"$(CANDIDATE_DIR).stage/ARC_AI_Relay_Chat_Literature.pdf"
	@revision=`/usr/bin/git rev-parse "$(TAG)^{commit}"`; \
		digest=`/bin/cat "$(KNOWLEDGE_SHA)"`; \
		"$(ARC_DEV)" candidate-manifest --version "$(VERSION)" --tag "$(TAG)" \
			--revision "$$revision" --dmg "$(CANDIDATE_DIR).stage/ARC-$(VERSION).dmg" \
			--literature \
			"$(CANDIDATE_DIR).stage/ARC_AI_Relay_Chat_Literature.pdf" \
			--source "$(CANDIDATE_DIR).stage/ARC-$(VERSION)-source.tar.gz" \
			--knowledge-sha256 "$$digest" \
			--output "$(CANDIDATE_DIR).stage/ARC-$(VERSION)-MANIFEST.json"
	@/bin/mv "$(CANDIDATE_DIR).stage" "$(CANDIDATE_DIR)"

release-dvt:
	@test -n "$(DVT_REPORT)" && test "$(DVT_REPORT)" != "$(DVT_REPORT:.txt=)" || \
		{ echo "DVT_REPORT must name an external completed .txt report" >&2; exit 2; }
	@case "$(DVT_REPORT)" in /*) ;; *) echo "DVT_REPORT must be absolute" >&2; exit 2;; esac
	"$(ARC_DEV)" dvt-check --report "$(DVT_REPORT)" \
		--candidate-manifest "$(CANDIDATE_MANIFEST)"

release-prepared-check: release-environment release-dvt
	/usr/bin/hdiutil verify "$(CANDIDATE_DMG)"
	/usr/bin/codesign --verify --verbose=2 "$(CANDIDATE_DMG)"
	/usr/bin/xcrun stapler validate "$(CANDIDATE_DMG)"
	@set -eu; tmp=$$(/usr/bin/mktemp -d "/private/tmp/arc-release-check.XXXXXX"); \
		mount="$$tmp/mount"; source="$$tmp/source"; \
		/bin/mkdir -p "$$mount" "$$source"; \
		trap '/usr/bin/hdiutil detach "$$mount" >/dev/null 2>&1 || true' \
			EXIT HUP INT TERM; \
		/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$$mount" \
			"$(CANDIDATE_DMG)" >/dev/null; \
		"$(ARC_DEV)" app-check --app "$$mount/ARC.app" \
			--version "$(VERSION)" --release; \
		/usr/bin/codesign --verify --deep --strict --verbose=2 \
			"$$mount/ARC.app"; \
		/usr/sbin/spctl --assess --type execute --verbose=2 "$$mount/ARC.app"; \
		/usr/bin/xcrun stapler validate "$$mount/ARC.app"; \
		test "`/usr/bin/lipo -archs "$$mount/ARC.app/Contents/MacOS/ARC"`" = arm64; \
		test "`/usr/bin/lipo -archs \
			"$$mount/ARC.app/Contents/Resources/install/bin/arc"`" = arm64; \
		/usr/bin/hdiutil detach "$$mount" >/dev/null; \
		/usr/bin/tar -xzf "$(CANDIDATE_SOURCE)" -C "$$source"; \
		"$(ARC_DEV)" source-check --source "$$source/ARC-$(VERSION)"; \
		trap - EXIT HUP INT TERM; \
		/bin/rm -rf -- "$$tmp"

release-seal: release-prepared-check
	@/bin/rm -rf -- "$(FINAL_DIR).stage" "$(FINAL_DIR)"
	@/bin/mkdir -p "$(FINAL_DIR).stage"
	/usr/bin/install -m 644 "$(CANDIDATE_DMG)" "$(FINAL_DIR).stage/ARC-$(VERSION).dmg"
	/usr/bin/install -m 644 "$(CANDIDATE_SOURCE)" \
		"$(FINAL_DIR).stage/ARC-$(VERSION)-source.tar.gz"
	/usr/bin/install -m 644 "$(CANDIDATE_LITERATURE)" \
		"$(FINAL_DIR).stage/ARC_AI_Relay_Chat_Literature.pdf"
	/usr/bin/install -m 644 "$(CANDIDATE_MANIFEST)" \
		"$(FINAL_DIR).stage/ARC-$(VERSION)-MANIFEST.json"
	/usr/bin/install -m 644 "$(DVT_REPORT)" \
		"$(FINAL_DIR).stage/ARC-$(VERSION)-DVT-REPORT.txt"
	@app_id=`/usr/bin/plutil -extract id raw -o - "$(BUILD)/notary/app.json" | \
		/usr/bin/tr '[:upper:]' '[:lower:]'`; \
		dmg_id=`/usr/bin/plutil -extract id raw -o - "$(BUILD)/notary/dmg.json" | \
		/usr/bin/tr '[:upper:]' '[:lower:]'`; \
		"$(ARC_DEV)" release-metadata \
			--candidate-manifest "$(FINAL_DIR).stage/ARC-$(VERSION)-MANIFEST.json" \
			--dvt-report "$(FINAL_DIR).stage/ARC-$(VERSION)-DVT-REPORT.txt" \
			--signing-identity "$(SIGNING_IDENTITY)" \
			--app-notarization-id "$$app_id" --dmg-notarization-id "$$dmg_id" \
			--output "$(FINAL_DIR).stage/RELEASE-METADATA.json"
	"$(ARC_DEV)" checksums --directory "$(FINAL_DIR).stage" --version "$(VERSION)" \
		--output "$(FINAL_DIR).stage/SHA256SUMS"
	"$(ARC_DEV)" release-check --directory "$(FINAL_DIR).stage" \
		--version "$(VERSION)"
	@/bin/mv "$(FINAL_DIR).stage" "$(FINAL_DIR)"

clean:
	/bin/rm -rf -- "$(BUILD)" "$(OUTPUT)" ".build"
