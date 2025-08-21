main: src/main.odin
	odin build src -out:bin/main

run: main
	./bin/main

debug: src/main.odin
	odin build src -out:bin/debug -debug