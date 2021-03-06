ROOT_DIR := $(shell dirname $(realpath $(MAKEFILE_LIST)))

SOLC=$(ROOT_DIR)/node_modules/.bin/solcjs
PYTHON=python3
NPM=npm
GANACHE=$(ROOT_DIR)/node_modules/.bin/ganache-cli
TRUFFLE=$(ROOT_DIR)/node_modules/.bin/truffle

NAME=shwop
DOCKER_TAG_NAME=harryr/$(NAME):latest
DIST_BINARY=dist/$(NAME)

UTIL_IMPORTS=$(ROOT_DIR)/utils/extract-imports.sh

CONTRACTS=HTLC
CONTRACTS_BIN=$(addprefix build/,$(addsuffix .bin,$(CONTRACTS)))
CONTRACTS_ABI=$(addprefix abi/,$(addsuffix .abi,$(CONTRACTS)))

PYLINT_IGNORE=C0330,invalid-name,line-too-long,missing-docstring,bad-whitespace,consider-using-ternary,wrong-import-position,wrong-import-order,trailing-whitespace


all: check-prereqs contracts python-pyflakes test python-pylint

check-prereqs:
	@if [ ! -f "$(SOLC)" ]; then \
		echo -e "Dependencies not found!\nInstall prerequisites first! See README.md"; \
		false; \
	fi

clean:
	rm -rf build chaindata dist
	find . -name '*.pyc' -exec rm '{}' ';'
	find . -name '__pycache__' -exec rm -rf '{}' ';'
	rm -rf *.pyc *.pdf *.egg-info *.pid *.log
	rm -f lextab.py yacctab.py


#######################################################################
#
# Packaging and distribution

docker-build: docker-build-glibc

# Uses PyInstaller to crate a self-contained executable, packages in Docker file
docker-build-glibc: $(DIST_BINARY)
	docker build --rm=true -t $(DOCKER_TAG_NAME) -f utils/Dockerfile.alpine-glibc .

# Uses jfloff/alpine-python image for traditional python installation
docker-build-python:
	docker build --rm=true -t $(DOCKER_TAG_NAME) -f utils/Dockerfile.alpine-python .

docker-run:
	docker run --rm=true -ti $(DOCKER_TAG_NAME) --help

bdist:
	$(PYTHON) setup.py bdist_egg --exclude-source-files
	$(PYTHON) setup.py bdist_wheel --universal

dist:
	mkdir -p $@

$(DIST_BINARY): utils/pyinstaller.spec dist
	$(PYTHON) -mPyInstaller --clean -p $(ROOT_DIR) $<


#######################################################################
#
# Linting and anti-retardery measures

python-pyflakes:
	$(PYTHON) -mpyflakes $(NAME)

python-pylint:
	$(PYTHON) -mpylint -d $(PYLINT_IGNORE) $(NAME) || true

python-lint: python-pyflakes python-pylint

solidity-lint:
	$(NPM) run lint

lint: solidity-lint python-lint


#######################################################################
#
# Install dependencies / requirements etc. for Python and NodeJS
#

nodejs-requirements:
	$(NPM) install

# Useful shortcut for development, install packages to user path by default
python-pip-user:
	mkdir -p $(HOME)/.pip/
	echo -e "[global]\nuser = true\n" > $(HOME)/.pip/pip.conf

python-requirements: requirements.txt
	$(PYTHON) -mpip install -r $<

python-dev-requirements: requirements-dev.txt
	$(PYTHON) -mpip install -r $<

requirements-dev: nodejs-requirements python-dev-requirements

requirements: python-requirements

fedora-dev:
	# use `nvm` to manage nodejs versions, rather than relying on system node
	curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash
	nvm install --lts


#######################################################################
#
# Builds Solidity contracts and ABI files
#

contracts: $(CONTRACTS_BIN) $(CONTRACTS_ABI)

abi:
	mkdir -p abi

abi/%.abi: build/%.abi abi contracts/%.sol
	cp $< $@

build:
	mkdir -p build

build/%.abi: build/%.bin

build/%.bin: contracts/%.sol build
	$(eval contract_name := $(shell echo $(shell basename $<) | cut -f 1 -d .))
	cd $(shell dirname $<) && $(SOLC) --optimize -o ../build --asm --bin --overwrite --abi $(shell basename $<) $(shell $(UTIL_IMPORTS) $<)
	cp build/$(contract_name)_sol_$(contract_name).bin build/$(contract_name).bin
	cp build/$(contract_name)_sol_$(contract_name).abi build/$(contract_name).abi

build/%.combined.bin: build/%.combined.sol
	$(SOLC) -o build --asm --bin --overwrite --abi $<

build/%.combined.sol: contracts/%.sol build
	cat $< | sed -e 's/\bimport\(\b.*\);/#include \1/g' | cpp -Icontracts | sed -e 's/^#.*$$//g' > $@


#######################################################################
#
# Testing and unit test harnesses
#

# runs an instance of testrpc in background, then waits for it to be ready
travis-testrpc-start: travis-testrpc-stop
	$(NPM) run testrpca > .testrpc.log & echo $$! > .testrpc.pid
	while true; do echo -n . ; curl http://localhost:8545 &> /dev/null && break || sleep 1; done

# Stops previ
travis-testrpc-stop:
	if [ -f .testrpc.pid ]; then kill `cat .testrpc.pid` || true; rm -f .testrpc.pid; fi

travis: travis-testrpc-start truffle-deploy-a contracts test $(DIST_BINARY) lint


testrpc-a:
	$(NPM) run testrpca

testrpc-b:
	$(NPM) run testrpcb

test-js:
	$(NPM) run test

test-unit:
	$(PYTHON) -m unittest discover test/

test-coordserver:
	$(PYTHON) -m$(NAME) htlc coordinator --contract 0xcfeb869f69431e42cdb54a4f4f105c19c080a601

test-coordclient:
	PYTHONPATH=. $(PYTHON) ./test/test_coordclient.py

test: test-unit test-js


#######################################################################
#
# Truffle utils
#

truffle-deploy-a:
	$(TRUFFLE) deploy --network testrpca --reset

truffle-deploy-b:
	$(TRUFFLE) deployb --network testrpcb --reset

truffle-console:
	$(TRUFFLE) console