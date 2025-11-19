.PHONY: test

test:
	odin test . --all-packages --o:speed
