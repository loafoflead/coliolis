main: src/main.odin
	odin build src -out:bin/main -vet-unused -vet-using-stmt -vet-using-param -vet-style -vet-cast

run: main
	./bin/main

debug: src/main.odin
	odin build src -out:bin/debug -debug