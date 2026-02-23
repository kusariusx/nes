.PHONY: test

TARGET := nes
RUN_TARGET_COMMAND := ./$(TARGET)

ROM_PATH := "test/other/AccuracyCoin/AccuracyCoin.nes"

test:
	odin test . --all-packages --o:speed

run:
	$(RUN_TARGET_COMMAND) "$(ROM_PATH)"

build:
	odin build . --o:speed --microarch:native --no-bounds-check --no-type-assert --disable-assert --out:$(TARGET)

build-debug:
	odin build . --debug --o:none --out:$(TARGET)

build-debug-speed:
	odin build . --debug --o:speed --microarch:native --no-bounds-check --no-type-assert --disable-assert --out:$(TARGET)

asm:
	odin build . --o:speed --build-mode:asm --microarch:native --no-bounds-check --no-type-assert --disable-assert --out:nes.asm

clean:
	rm -rf nes nes.dSYM

sample:
	./tools/samply record --rate 10000 $(RUN_TARGET_COMMAND) "$(ROM_PATH)"
