.PHONY: all build run clean python-setup

BUILD_DIR := build
IMAGE_SRC ?= image/naturestock.jpg

STAGE1_SRC := src/stage1.s
STAGE2_SRC := src/stage2.s
CONSTANTS_INC := src/constants.inc

IMAGE_BIN := $(BUILD_DIR)/image.bin
STAGE1_BIN := $(BUILD_DIR)/stage1.bin
STAGE2_BIN := $(BUILD_DIR)/stage2.bin
BOOT_BIN := $(BUILD_DIR)/boot.bin

FASM := ./utils/fasm.sh
PYTHON_SETUP := ./utils/python.sh
CONVERT := utils/convert.py

all: build

build: $(BOOT_BIN)

$(IMAGE_BIN): $(IMAGE_SRC) $(CONVERT) utils/requirements.txt
	@echo "Runing conversion script on $(IMAGE_SRC)..."
	python3 $(CONVERT) "$(IMAGE_SRC)" "$@"

$(STAGE2_BIN): $(STAGE2_SRC) $(CONSTANTS_INC)
	@echo "Assembling stage 2..."
	$(FASM) "$(abspath $(STAGE2_SRC))" "$(abspath $@)"

$(STAGE1_BIN): $(STAGE1_SRC) $(CONSTANTS_INC) $(STAGE2_BIN) $(IMAGE_BIN)
	@echo "Assembling stage 1..."
	$(FASM) \
		-d STAGE2_SIZE_B=$$(wc -c < "$(STAGE2_BIN)" | tr -d '[:space:]') \
		-d IMAGE_SIZE_B=$$(wc -c < "$(IMAGE_BIN)" | tr -d '[:space:]') \
		"$(abspath $(STAGE1_SRC))" \
		"$(abspath $@)"

$(BOOT_BIN): $(STAGE1_BIN) $(STAGE2_BIN) $(IMAGE_BIN)
	@echo "Creating bootable image..."
	cat $(STAGE1_BIN) $(STAGE2_BIN) $(IMAGE_BIN) > $@
	@printf 'Built %s\n' "$@"

run: $(BOOT_BIN)
	qemu-system-i386 -drive format=raw,file="$(abspath $(BOOT_BIN))"

python-setup: utils/python.sh
	$(PYTHON_SETUP)

clean:
	rm -rf $(BUILD_DIR)/*
