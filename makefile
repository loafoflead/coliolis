main: src/main.odin
	odin build src -out:bin/main -vet-using-stmt -vet-using-param -vet-style -vet-cast

main-strict:
	odin build src -out:bin/main -vet-using-stmt -vet-using-param -vet-style -vet-cast -vet-unused

run: main
	./bin/main

debug: src/main.odin
	odin build src -out:bin/debug -debug