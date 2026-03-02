.PHONY: test

TARGET := nes
RUN_TARGET_COMMAND := ./$(TARGET)
DEBUG_FEATURES := false

ROM_PATH := "games/Super_mario_brothers.nes"

test:
	odin test . --all-packages --o:speed

run:
	$(RUN_TARGET_COMMAND) $(ROM_PATH)

build:
	odin build . --o:speed --microarch:native --no-bounds-check --no-type-assert --disable-assert --out:$(TARGET) --define:DEBUG_FEATURES=$(DEBUG_FEATURES)

build-debug:
	odin build . --o:speed --microarch:native --no-bounds-check --no-type-assert --disable-assert --out:$(TARGET) --define:DEBUG_FEATURES=$(DEBUG_FEATURES) --debug

asm:
	odin build . --o:speed --build-mode:asm --microarch:native --no-bounds-check --no-type-assert --disable-assert --out:nes.S

clean:
	rm -rf nes nes.dSYM

sample:
	./tools/samply record --rate 10000 $(RUN_TARGET_COMMAND) $(ROM_PATH)
