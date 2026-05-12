.PHONY: all build run clean

BUILD_DIR := build
BUILD_STAMP := $(BUILD_DIR)/.dir
UV_CACHE_DIR := /tmp/uv-cache

IMAGE_SRC := image/naturestock.jpg
IMAGE_BIN := $(BUILD_DIR)/image.bin

STAGE1_SRC := src/stage1.s
STAGE2_SRC := src/stage2.s
CONSTANTS_INC := src/constants.inc

STAGE1_BIN := $(BUILD_DIR)/stage1.bin
STAGE2_BIN := $(BUILD_DIR)/stage2.bin
BOOT_BIN := $(BUILD_DIR)/boot.bin

all: $(BOOT_BIN)

build: $(BOOT_BIN)

$(BUILD_STAMP):
	mkdir -p $(BUILD_DIR)
	touch $@

$(IMAGE_BIN): $(IMAGE_SRC) utils/convert.py | $(BUILD_STAMP)
	UV_CACHE_DIR=$(UV_CACHE_DIR) uv run utils/convert.py $< $@

$(STAGE2_BIN): $(STAGE2_SRC) $(CONSTANTS_INC) | $(BUILD_STAMP)
	fasm $< $@

$(STAGE1_BIN): $(STAGE1_SRC) $(CONSTANTS_INC) $(STAGE2_BIN) $(IMAGE_BIN) | $(BUILD_STAMP)
	fasm \
	  -d STAGE2_SIZE_B=$(shell stat -L -c %s $(STAGE2_BIN)) \
	  -d IMAGE_SIZE_B=$(shell stat -L -c %s $(IMAGE_BIN)) \
	  -d IMAGE_VALIDATION_VALUE=$(shell od -An -tu2 -N2 $(IMAGE_BIN) | tr -d '[:space:]') \
	  $< $@

$(BOOT_BIN): $(STAGE1_BIN) $(STAGE2_BIN) $(IMAGE_BIN) | $(BUILD_STAMP)
	cat $^ > $@

run: $(BOOT_BIN)
	qemu-system-i386 -drive format=raw,file=$<

clean:
	rm -f $(BUILD_DIR)/*.bin
