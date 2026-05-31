ARCH       ?= x86_64
IMAGE_NAME ?= dasel
IMAGE_TAG  ?= 3.3.1
IMAGE_REF   = $(IMAGE_NAME):$(IMAGE_TAG)
TARBALL     = dasel.tar

.PHONY: all build test package package-test image image-test clean help

all: build test

build: package image

# --- Keys (one-time, only regenerated if missing) ---

keys/melange.rsa:
	docker compose run --rm melange keygen keys/melange.rsa

# --- Package ---

package: packages/$(ARCH)/dasel-$(IMAGE_TAG)-r0.apk

packages/$(ARCH)/dasel-$(IMAGE_TAG)-r0.apk: keys/melange.rsa melange/dasel.yaml melange/CVE-2026-33320.patch
	docker compose run --rm melange build melange/dasel.yaml \
		--arch $(ARCH) \
		--signing-key keys/melange.rsa

package-test: packages/$(ARCH)/dasel-$(IMAGE_TAG)-r0.apk
	docker compose run --rm melange test melange/dasel.yaml --arch $(ARCH)

# --- Image ---

image: $(TARBALL)

$(TARBALL): packages/$(ARCH)/dasel-$(IMAGE_TAG)-r0.apk apko/dasel.yaml
	docker compose run --rm apko build apko/dasel.yaml \
		$(IMAGE_REF) $(TARBALL) \
		--arch $(ARCH) \
		--sbom-path sbom/

image-test: $(TARBALL)
	docker load --input $(TARBALL)
	bash tests/test.sh

# --- Test ---

test: package-test image-test

# --- Clean ---

clean:
	rm -rf packages/ sbom/ $(TARBALL)
	rm -f keys/melange.rsa keys/melange.rsa.pub

# --- Help ---

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all            Build everything and run all tests (default)"
	@echo "  build          Build package and image"
	@echo "  package        Build the APK package with melange"
	@echo "  package-test   Run melange package tests"
	@echo "  image          Build the OCI image with apko"
	@echo "  image-test     Load and test the container image"
	@echo "  test           Run all tests (package + image)"
	@echo "  clean          Remove all generated artifacts (keys, packages, sbom, tarball)"
	@echo "  help           Show this help"
	@echo ""
	@echo "Variables:"
	@echo "  ARCH           Target architecture (default: x86_64)"
	@echo "  IMAGE_NAME     Image name (default: dasel)"
	@echo "  IMAGE_TAG      Image tag (default: 3.3.1)"
