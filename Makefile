.PHONY: all build run clean

all: build

build:
	./utils/build.sh

run:
	./utils/run.sh

clean:
	rm -rf build
