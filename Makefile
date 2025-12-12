.PHONY: test

TARGET := nes
RUN_TARGET_COMMAND := ./$(TARGET)

test:
	odin test . --all-packages --o:speed

run:
	$(RUN_TARGET_COMMAND)

build:
	odin build . --o:speed --microarch:native --no-bounds-check --disable-assert --out:$(TARGET)

build-debug:
	odin build . --debug --o:none --out:$(TARGET)

clean:
	rm -rf nes nes.dSYM

capture-profile:
	./scripts/capture-profile.sh $(TARGET)
