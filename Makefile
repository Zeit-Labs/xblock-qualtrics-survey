#!/usr/bin/make -f
package_name := qualtricssurvey
module_root := ./$(package_name)
css_files := $(patsubst %.less, %.css, $(wildcard ./$(module_root)/public/*.less))
html_files := $(wildcard ./$(module_root)/templates/*.html)
js_files := $(wildcard ./$(module_root)/public/*.js)
files_with_translations := $(js_files) $(html_files)
translation_root := $(module_root)/translations
po_files := $(wildcard $(translation_root)/*/LC_MESSAGES/django.po)
ifneq ($(strip $(language)),)
    po_files := $(po_files) $(translation_root)/$(language)/LC_MESSAGES/django.po
endif
ifeq ($(strip $(po_files)),)
    po_files = $(translation_root)/en/LC_MESSAGES/django.po
endif

.PHONY: help
help:  ## This.
	@perl -ne 'print if /^[a-zA-Z_-]+:.*## .*$$/' $(MAKEFILE_LIST) \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: runserver
runserver: build_docker  ## Run server inside XBlock Workbench container
	$(docker_run) $(_NAME)

.PHONY: clean
clean:  ## Remove build artifacts
	tox -e clean
	rm -rf reports/cover
	rm -rf .tox/
	rm -rf *.egg-info/
	rm -rf .eggs/
	rm -rf package-lock.json
	rm -rf node_modules/
	find . -name '*.pyc' -delete
	find . -name __pycache__ -delete

.PHONY: requirements
requirements: requirements_js requirements_py  ## Install all required packages
	pip install -r requirements/pip.txt

.PHONY: requirements_py
requirements_py:  # Install required python packages
	pip install tox
	pip install -r requirements/base.txt

.PHONY: requirements_ci
requirements_ci:  requirements_js # Install ci requirements
	pip install -r requirements/ci.txt

.PHONY: requirements_js
requirements_js:  # Install required packages
	npm install

.PHONY: static
static: requirements_js $(css_files)  ## Compile the less->css
$(module_root)/public/%.css: $(module_root)/public/%.less
	@echo "$< -> $@"
	node_modules/less/bin/lessc $< $@

.PHONY: test
test: requirements requirements_js  ## Run all quality checks and unit tests
	tox -p all

COMMON_CONSTRAINTS_TXT=requirements/common_constraints.txt
.PHONY: $(COMMON_CONSTRAINTS_TXT)
$(COMMON_CONSTRAINTS_TXT):
	wget -O "$(@)" https://raw.githubusercontent.com/edx/edx-lint/master/edx_lint/files/common_constraints.txt || touch "$(@)"

upgrade: export CUSTOM_COMPILE_COMMAND=make upgrade
upgrade: $(COMMON_CONSTRAINTS_TXT)  ## update the requirements/*.txt files with the latest packages satisfying requirements/*.in
	pip install -q -r requirements/pip_tools.txt
	pip-compile --upgrade --allow-unsafe -o requirements/pip.txt requirements/pip.in
	pip-compile --upgrade -o requirements/pip_tools.txt requirements/pip_tools.in
	pip install -qr requirements/pip.txt
	pip install -qr requirements/pip_tools.txt
	pip-compile --upgrade -o requirements/base.txt requirements/base.in
	pip-compile --upgrade -o requirements/test.txt requirements/test.in
	pip-compile --upgrade -o requirements/quality.txt requirements/quality.in
	pip-compile --upgrade -o requirements/tox.txt requirements/tox.in
	pip-compile --upgrade -o requirements/ci.txt requirements/ci.in

$(translation_root)/%/LC_MESSAGES/django.po: $(files_with_translations)
	mkdir -p $(@D)
	./manage.py makemessages -l $(shell echo $(@) | cut -d'/' -f 3)
.PHONY: translations
translations: $(po_files)  ## Update translation files
	@echo
	@echo 'Translations updated.'
	@echo "You can add a new language like this:"
	@echo '    make $(@) language=fr'
	@echo 'where `fr` is the language code.'
	@echo

_NAME=$(package_name):latest
_VOLUME=-v '$(PWD):/root/xblock'
_PORT=
runserver: _PORT = -p 8000:8000
docker_test: _VOLUME = -v '$(PWD)/reports:/root/xblock/reports'
docker_run=docker run $(_PORT) $(_VOLUME) --rm -it
docker_make=$(docker_run) --entrypoint make $(_NAME)
docker_make_args=language=$(language) -C /root/xblock
docker_make_more=$(docker_make) $(docker_make_args)

.PHONY: build_docker
build_docker:
	docker build -t $(_NAME) .
.PHONY: docker_static docker_test docker_translations
define run-in-docker
$(docker_make_more) $(patsubst docker_%, %, $@)
endef
docker_shell:
	$(docker_run) --entrypoint /bin/bash $(_NAME)
docker_static: ; make build_docker; $(run-in-docker)  ## Compile static assets in docker container
docker_translations: ; make build_docker; $(run-in-docker)  ## Update translation files in docker container
docker_test: ; make build_docker; $(run-in-docker)  ## Run tests in docker container
