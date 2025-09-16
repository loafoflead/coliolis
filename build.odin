package build

import "core:c/libc"
import "core:os"
import "core:strings"
import "base:runtime"
import "core:time"
import "core:log"

// stolen from https://github.com/tsoding/nobuild/blob/master/nobuild.h
// which was apparently stolen from https://github.com/zhiayang/nabs
auto_rebuild :: proc(args: []string, allocator := context.allocator) -> (should_return: bool) {
	binary_path := args[0]
	source_path := #file

	bin_modif, bok := get_file_last_modified(binary_path, allocator)
	src_modif, sok := get_file_last_modified(source_path, allocator)
	if !bok || !sok {
		log.panicf("Could not auto rebuild, failed to get last modified time of binary or source path.")
	}
	// if the build binary was generate before the source, the 
	// source has changed and must regenerate the binary
	if time.since(bin_modif) > time.since(src_modif) {
		log.info("Rebuilding the build script...")
		cmd := command_new("odin", "build", source_path, "-file", "-out:build")
		if command_run(&cmd, silent=true) != 0 do return true

		command_append(&cmd, "./build")
		command_append(&cmd, ..args[1:])
		if command_run(&cmd) != 0 do return true
		should_return = true
	}

	return
}

get_file_last_modified :: proc(path: string, allocator: runtime.Allocator) -> (time: time.Time = {}, ok: bool = false) {
	handle, herr := os.open(path)
	if herr != nil {
		log.errorf("Failed to open file `%s` for reading", path)
		return
	}

	file_info, infoerr := os.fstat(handle, allocator)
	if infoerr != nil {
		log.errorf("Could not get file info of `%s`", path)
		return
	}

	time = file_info.modification_time
	ok = true

	return
}

Command :: struct {
	values: [dynamic]string,
}

command_clear :: proc(c: ^Command) {
	clear(&c.values)
}

// command_append :: proc(c: ^Command, args: []string) {
// 	for arg in args do append(&c.values, arg)
// }

command_append :: proc(c: ^Command, args: ..string) {
	for arg in args do append(&c.values, arg)	
}

command_new :: proc(name: string, args: ..string, allocator := context.allocator) -> Command {
	c: Command
	c.values = make([dynamic]string, allocator)

	append(&c.values, name)
	for arg in args do append(&c.values, arg)
	return c
}

command_run :: proc(c: ^Command, and_clear := true, silent: bool = false, allocator := context.temp_allocator) -> (return_code: i32) {
	s := strings.builder_make(allocator)
	for val in c.values {
		strings.write_string(&s, val)
		strings.write_string(&s, " ")
	}
	str := strings.to_string(s)
	if !silent do log.infof("%s", str)

	ret := libc.system(strings.to_cstring(&s))

	if and_clear {
		command_clear(c)
	}

	return ret
}

make_dir :: proc(path: string, allow_exists : bool = true) -> (ok: bool) {
	// if allow_exists && os.exists(path) {
	// 	log.infof("Directory '%s' exists already, nothing changed.", path)
	// 	return true
	// }
	// else {
	// 	log.errorf("Failed to create directory '%s', it already exists.", path)
	// 	return false
	// }

	direrror := os.make_directory(path)
	if direrror == nil {
		log.infof("Created directory '%s'", path)
		return true	
	}
	
	switch direrror {
	case os.EEXIST:
		if !allow_exists {
			log.errorf("Failed to create directory '%s', it already exists.", path)
			return false
		}
		else {
			log.warnf("Directory '%s' exists already, nothing changed.", path)
			return true
		}
	case:
		log.errorf("Failed to create directory '%s': %s", path, os.error_string(direrror))
	}
	return false
}

import "core:flags"

Build_Mode :: enum {
	build,
	run,
	check,
}

Cmd_Options :: struct {
	debug: bool,
	vet: bool,
	assets: bool,
	mode: Build_Mode,
}

main :: proc() {
	context.logger = log.create_console_logger() // TODO: free? or not?

	defer log.destroy_console_logger(context.logger)
	defer free_all(context.temp_allocator)

	if auto_rebuild(os.args) do return

	opts: Cmd_Options
	err := flags.parse(&opts, os.args[1:], allocator = context.temp_allocator)
	if err != nil {
		log.fatalf("Failed to parse command line args: %v", err)
		return
	}

	if !make_dir("./bin") do return

	c: Command
	command_append(&c, "odin")
	switch opts.mode {
	case .run:
		command_append(&c, "run")
	case .check:
		command_append(&c, "check")
	case .build:
		command_append(&c, "build")
	}
	command_append(&c, "src")

	vets : []string = {"-vet-using-stmt", "-vet-using-param", "-vet-style", "-vet-cast"}
	command_append(&c, ..vets)

	if opts.vet {
		command_append(&c, "-vet-unused")
	}

	if opts.mode != .check {
		if opts.debug {
			command_append(&c, "-debug", "-out:bin/debug")
		}
		else {
			command_append(&c, "-out:bin/main")
		}
	}

	if opts.assets {
		log.info("Generating assets...")
		command_append(&c, "-define:__GEN_ASSETS__=true")
	}

	command_run(&c)
}