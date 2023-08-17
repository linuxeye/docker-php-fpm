ifneq (,)
.error This Makefile requires GNU Make.
endif

# Ensure additional Makefiles are present
MAKEFILES = Makefile.docker Makefile.lint
$(MAKEFILES): URL=https://raw.githubusercontent.com/devilbox/makefiles/master/$(@)
$(MAKEFILES):
	@if ! (curl --fail -sS -o $(@) $(URL) || wget -O $(@) $(URL)); then \
		echo "Error, curl or wget required."; \
		echo "Exiting."; \
		false; \
	fi
include $(MAKEFILES)

# Set default Target
.DEFAULT_GOAL := help


# -------------------------------------------------------------------------------------------------
# Default configuration
# -------------------------------------------------------------------------------------------------
DOCKER_PULL_BASE_IMAGES_IGNORE = devilbox-slim-base devilbox-work-help devilbox-work-tools
# Own vars
TAG        = latest

# Makefile.docker overwrites
NAME       = PHP
#VERSION    = 5.5
IMAGE      = bypanel/php-fpm
#FLAVOUR    = debian
#STAGE      = base
FILE       = Dockerfile-$(VERSION)
DIR        = Dockerfiles/$(STAGE)

ifeq ($(strip $(TAG)),latest)
DOCKER_TAG = $(VERSION)-$(STAGE)
BASE_TAG   = $(VERSION)-base
MODS_TAG   = $(VERSION)-mods
PROD_TAG   = $(VERSION)-prod
SLIM_TAG   = $(VERSION)-slim
WORK_TAG   = $(VERSION)-work
else
DOCKER_TAG = $(VERSION)-$(STAGE)-$(TAG)
BASE_TAG   = $(VERSION)-base-$(TAG)
MODS_TAG   = $(VERSION)-mods-$(TAG)
PROD_TAG   = $(VERSION)-prod-$(TAG)
SLIM_TAG   = $(VERSION)-slim-$(TAG)
WORK_TAG   = $(VERSION)-work-$(TAG)
endif
ARCH       = linux/amd64


# Makefile.lint overwrites
FL_IGNORES  = .git/,.github/,tests/,*.mypy_cache/
SC_IGNORES  = .git/,.github/,tests/
JL_IGNORES  = .git/,.github/,*.mypy_cache*


# -------------------------------------------------------------------------------------------------
# Default Target
# -------------------------------------------------------------------------------------------------
.PHONY: help
help:
	@echo "lint                                     Lint project files and repository"
	@echo
	@echo "build [ARCH=...] [TAG=...]               Build Docker image"
	@echo "rebuild [ARCH=...] [TAG=...]             Build Docker image without cache"
	@echo "push [ARCH=...] [TAG=...]                Push Docker image to Docker hub"
	@echo
	@echo "manifest-create [ARCHES=...] [TAG=...]   Create multi-arch manifest"
	@echo "manifest-push [TAG=...]                  Push multi-arch manifest"
	@echo
	@echo "test [ARCH=...]                          Test built Docker image"
	@echo


# -------------------------------------------------------------------------------------------------
# Overwrite Targets
# -------------------------------------------------------------------------------------------------

# Append additional target to lint
lint: lint-changelog
lint: lint-ansible

###
### Ensures CHANGELOG has an entry
###
.PHONY: lint-changelog
lint-changelog:
	@echo "################################################################################"
	@echo "# Lint Changelog"
	@echo "################################################################################"
	@\
	GIT_CURR_MAJOR="$$( git tag | sort -V | tail -1 | sed 's|\.[0-9]*$$||g' )"; \
	GIT_CURR_MINOR="$$( git tag | sort -V | tail -1 | sed 's|^[0-9]*\.||g' )"; \
	GIT_NEXT_TAG="$${GIT_CURR_MAJOR}.$$(( GIT_CURR_MINOR + 1 ))"; \
	if ! grep -E "^## Release $${GIT_NEXT_TAG}$$" CHANGELOG.md >/dev/null; then \
		echo "[ERR] Missing '## Release $${GIT_NEXT_TAG}' section in CHANGELOG.md"; \
		exit 1; \
	else \
		echo "[OK] Section '## Release $${GIT_NEXT_TAG}' present in CHANGELOG.md"; \
	fi
	@echo

###
### Ensures Ansible Dockerfile generation is current
###
.PHONY: lint-ansible
lint-ansible: gen-dockerfiles
	@git diff --quiet || { echo "Build Changes"; git diff; git status; false; }


# -------------------------------------------------------------------------------------------------
# Docker Targets
# -------------------------------------------------------------------------------------------------

# ---- ONLY FOR "mods" images ----
# When builds mods, we have a builder image and then copy everything to the final
# target image. In order to do so, we pass a build-arg EXT_DIR, which contains
# the variable directory of extensions to copy.
# The only way to "LAZY" fetch it, is by doing a call to the base image and populate
# a Makefile variable with its value upon call.
ifeq ($(strip $(STAGE)),mods)
EXT_DIR=$$( docker run --rm --platform $(ARCH) --entrypoint=php $(IMAGE):$(BASE_TAG) -r \
	'echo ini_get("extension_dir");'\
)
endif

# Use Buldkit for building
#export DOCKER_BUILDKIT=1

.PHONY: build
build: check-stage-is-set
build: check-parent-image-exists
build: ARGS+=--build-arg EXT_DIR=$(EXT_DIR) --build-arg ARCH=$(shell if [ "$(ARCH)" = "linux/amd64" ]; then echo "x86_64"; else echo "aarch64"; fi)
build: docker-arch-build

.PHONY: rebuild
rebuild: check-stage-is-set
rebuild: check-parent-image-exists
rebuild: ARGS+=--build-arg EXT_DIR=$(EXT_DIR) --build-arg ARCH=$(shell if [ "$(ARCH)" = "linux/amd64" ]; then echo "x86_64"; else echo "aarch64"; fi)
rebuild: docker-arch-rebuild

.PHONY: push
push: check-stage-is-set
push: check-version-is-set
push: docker-arch-push

.PHONY: tag
tag: check-stage-is-set
tag: check-version-is-set
tag:
	docker tag $(IMAGE):$(VERSION)-$(STAGE) $(IMAGE):$(DOCKER_TAG)


# -------------------------------------------------------------------------------------------------
# Save / Load Targets
# -------------------------------------------------------------------------------------------------
.PHONY: save
save: check-stage-is-set
save: check-version-is-set
save: check-current-image-exists
save: docker-save

.PHONY: load
load: docker-load

.PHONY: save-verify
save-verify: save
save-verify: load


# -------------------------------------------------------------------------------------------------
# Manifest Targets
# -------------------------------------------------------------------------------------------------
.PHONY: manifest-create
manifest-create: docker-manifest-create

.PHONY: manifest-push
manifest-push: docker-manifest-push


# -------------------------------------------------------------------------------------------------
# Test Targets
# -------------------------------------------------------------------------------------------------
.PHONY: test
test: check-stage-is-set
test: check-current-image-exists
test: test-integration
test: gen-readme

.PHONY: test-integration
test-integration:
	./tests/test.sh $(IMAGE) $(ARCH) $(VERSION) $(STAGE) $(DOCKER_TAG)


# -------------------------------------------------------------------------------------------------
# Generate Targets
# -------------------------------------------------------------------------------------------------

###
### Generate README (requires images to be built)
###
.PHONY: gen-readme
gen-readme: check-version-is-set
gen-readme: check-stage-is-set
gen-readme: _gen-readme-docs
gen-readme: _gen-readme-main

.PHONY: _gen-readme-docs
_gen-readme-docs:
	@echo "################################################################################"
	@echo "# Generate doc/php-modules.md for PHP $(VERSION) ($(IMAGE):$(DOCKER_TAG)) on $(ARCH)"
	@echo "################################################################################"
	./bin/gen-docs-php-modules.sh $(IMAGE) $(ARCH) $(STAGE) $(VERSION) || bash -x ./bin/gen-docs-php-modules.sh $(IMAGE) $(ARCH) $(STAGE) $(VERSION)
	git diff --quiet || { echo "Build Changes"; git diff; git status; false; }
	@echo

.PHONY: _gen-readme-main
_gen-readme-main:
	@echo "################################################################################"
	@echo "# Generate README.md"
	@echo "################################################################################"
	MODULES="$$( cat doc/php-modules.md \
		| grep href \
		| sed -e 's|</a.*||g' -e 's|.*">||g' \
		| sort -fu \
		| xargs -n1 sh -c 'echo "[\`$$1\`](php_modules/$$(echo "$${1}" | tr "[:upper:]" "[:lower:]")/)"' -- )"; \
	cat "README.md" \
		| perl -0 -pe "s#<!-- modules -->.*<!-- /modules -->#<!-- modules -->\n$${MODULES}\n<!-- /modules -->#s" \
		> "README.md.tmp"
	yes | mv -f "README.md.tmp" "README.md"
	git diff --quiet || { echo "Build Changes"; git diff; git status; false; }
	@echo

###
### Generate Dockerfiles
###
.PHONY: gen-dockerfiles
gen-dockerfiles:
	@echo "################################################################################"
	@echo "# Generating PHP modules"
	@echo "################################################################################"
	./bin/gen-php-modules.py $(MODS)
	@echo
	@echo "################################################################################"
	@echo "# Generating Tools"
	@echo "################################################################################"
	./bin/gen-php-tools.py $(TOOLS)
	@echo
	@echo "################################################################################"
	@echo "# Generating Dockerfiles"
	@echo "################################################################################"
	docker run --rm \
		$$(tty -s && echo "-it" || echo) \
		-e USER=ansible \
		-e MY_UID=$$(id -u) \
		-e MY_GID=$$(id -g) \
		-v ${PWD}:/data \
		-w /data/.ansible \
		cytopia/ansible:2.12-tools ansible-playbook generate.yml \
			-e ansible_python_interpreter=/usr/bin/python3 \
			-e \"{build_fail_fast: $(FAIL_FAST)}\" \
			--forks 50 \
			--diff $(ARGS)



# -------------------------------------------------------------------------------------------------
# HELPER TARGETS
# -------------------------------------------------------------------------------------------------

###
### Ensures the VERSION variable is set
###
.PHONY: check-version-is-set
check-version-is-set:
	@if [ "$(VERSION)" = "" ]; then \
		echo "This make target requires the VERSION variable to be set."; \
		echo "make <target> VERSION="; \
		echo "Exiting."; \
		exit 1; \
	fi

###
### Ensures the STAGE variable is set
###
.PHONY: check-stage-is-set
check-stage-is-set:
	@if [ "$(STAGE)" = "" ]; then \
		echo "This make target requires the STAGE variable to be set."; \
		echo "make <target> STAGE="; \
		echo "Exiting."; \
		exit 1; \
	fi
	@if [ "$(STAGE)" != "base" ] && [ "$(STAGE)" != "mods" ] && [ "$(STAGE)" != "prod" ] && [ "$(STAGE)" != "slim" ] && [ "$(STAGE)" != "work" ]; then \
		echo "Error, Flavour can only be one of 'base', 'mods', 'prod', 'slim' or 'work'."; \
		echo "Exiting."; \
		exit 1; \
	fi

###
### Checks if current image exists and is of correct architecture
###
.PHONY: check-current-image-exists
check-current-image-exists: check-stage-is-set
check-current-image-exists:
	@if [ "$$( docker images -q $(IMAGE):$(DOCKER_TAG) )" = "" ]; then \
		>&2 echo "Docker image '$(IMAGE):$(DOCKER_TAG)' was not found locally."; \
		>&2 echo "Either build it first or explicitly pull it from Dockerhub."; \
		>&2 echo "This is a safeguard to not automatically pull the Docker image."; \
		>&2 echo; \
		exit 1; \
	else \
		echo "OK: Image $(IMAGE):$(DOCKER_TAG) exists"; \
	fi; \
	OS="$$( docker image inspect $(IMAGE):$(DOCKER_TAG) --format '{{.Os}}' )"; \
	ARCH="$$( docker image inspect $(IMAGE):$(DOCKER_TAG) --format '{{.Architecture}}' )"; \
	if [ "$${OS}/$${ARCH}" != "$(ARCH)" ]; then \
		>&2 echo "Docker image '$(IMAGE):$(DOCKER_TAG)' has invalid architecture: $${OS}/$${ARCH}"; \
		>&2 echo "Expected: $(ARCH)"; \
		>&2 echo; \
		exit 1; \
	else \
		echo "OK: Image $(IMAGE):$(DOCKER_TAG) is of arch $${OS}/$${ARCH}"; \
	fi

###
### Checks if parent image exists and is of correct architecture
###
.PHONY: check-parent-image-exists
check-parent-image-exists: check-stage-is-set
check-parent-image-exists:
	@if [ "$(STAGE)" = "work" ]; then \
		if [ "$$( docker images -q $(IMAGE):$(SLIM_TAG) )" = "" ]; then \
			>&2 echo "Docker image '$(IMAGE):$(SLIM_TAG)' was not found locally."; \
			>&2 echo "Either build it first or explicitly pull it from Dockerhub."; \
			>&2 echo "This is a safeguard to not automatically pull the Docker image."; \
			>&2 echo; \
			exit 1; \
		fi; \
		OS="$$( docker image inspect $(IMAGE):$(SLIM_TAG) --format '{{.Os}}' )"; \
		ARCH="$$( docker image inspect $(IMAGE):$(SLIM_TAG) --format '{{.Architecture}}' )"; \
		if [ "$${OS}/$${ARCH}" != "$(ARCH)" ]; then \
			>&2 echo "Docker image '$(IMAGE):$(SLIM_TAG)' has invalid architecture: $${OS}/$${ARCH}"; \
			>&2 echo "Expected: $(ARCH)"; \
			>&2 echo; \
			exit 1; \
		fi; \
	elif [ "$(STAGE)" = "slim" ]; then \
		if [ "$$( docker images -q $(IMAGE):$(PROD_TAG) )" = "" ]; then \
			>&2 echo "Docker image '$(IMAGE):$(PROD_TAG)' was not found locally."; \
			>&2 echo "Either build it first or explicitly pull it from Dockerhub."; \
			>&2 echo "This is a safeguard to not automatically pull the Docker image."; \
			>&2 echo; \
			exit 1; \
		fi; \
		OS="$$( docker image inspect $(IMAGE):$(PROD_TAG) --format '{{.Os}}' )"; \
		ARCH="$$( docker image inspect $(IMAGE):$(PROD_TAG) --format '{{.Architecture}}' )"; \
		if [ "$${OS}/$${ARCH}" != "$(ARCH)" ]; then \
			>&2 echo "Docker image '$(IMAGE):$(PROD_TAG)' has invalid architecture: $${OS}/$${ARCH}"; \
			>&2 echo "Expected: $(ARCH)"; \
			>&2 echo; \
			exit 1; \
		fi; \
	elif [ "$(STAGE)" = "prod" ]; then \
		if [ "$$( docker images -q $(IMAGE):$(MODS_TAG) )" = "" ]; then \
			>&2 echo "Docker image '$(IMAGE):$(MODS_TAG)' was not found locally."; \
			>&2 echo "Either build it first or explicitly pull it from Dockerhub."; \
			>&2 echo "This is a safeguard to not automatically pull the Docker image."; \
			>&2 echo; \
			exit 1; \
		fi; \
		OS="$$( docker image inspect $(IMAGE):$(MODS_TAG) --format '{{.Os}}' )"; \
		ARCH="$$( docker image inspect $(IMAGE):$(MODS_TAG) --format '{{.Architecture}}' )"; \
		if [ "$${OS}/$${ARCH}" != "$(ARCH)" ]; then \
			>&2 echo "Docker image '$(IMAGE):$(MODS_TAG)' has invalid architecture: $${OS}/$${ARCH}"; \
			>&2 echo "Expected: $(ARCH)"; \
			>&2 echo; \
			exit 1; \
		fi; \
	elif [ "$(STAGE)" = "mods" ]; then \
		if [ "$$( docker images -q $(IMAGE):$(BASE_TAG) )" = "" ]; then \
			>&2 echo "Docker image '$(IMAGE):$(BASE_TAG)' was not found locally."; \
			>&2 echo "Either build it first or explicitly pull it from Dockerhub."; \
			>&2 echo "This is a safeguard to not automatically pull the Docker image."; \
			>&2 echo; \
			exit 1; \
		fi; \
		OS="$$( docker image inspect $(IMAGE):$(BASE_TAG) --format '{{.Os}}' )"; \
		ARCH="$$( docker image inspect $(IMAGE):$(BASE_TAG) --format '{{.Architecture}}' )"; \
		if [ "$${OS}/$${ARCH}" != "$(ARCH)" ]; then \
			>&2 echo "Docker image '$(IMAGE):$(BASE_TAG)' has invalid architecture: $${OS}/$${ARCH}"; \
			>&2 echo "Expected: $(ARCH)"; \
			>&2 echo; \
			exit 1; \
		fi; \
	fi;
