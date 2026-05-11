.PHONY: all run clean

all: run

build/boot.bin: src/boot.s
	fasm src/boot.s build/boot.bin

run: build/boot.bin
	qemu-system-i386 -drive format=raw,file=build/boot.bin

clean:
	rm -f build/boot.bin
