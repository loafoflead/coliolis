package build

import "core:c/libc"
import "core:os"
import "core:strings"
import "base:runtime"
import "core:time"
import "core:log"
import "core:fmt"

// stolen from https://github.com/tsoding/nobuild/blob/master/nobuild.h
// which was apparently stolen from https://github.com/zhiayang/nabs
auto_rebuild :: proc(args: []string, allocator := context.allocator) -> (should_return: bool) {
	binary_path := args[0]
	source_path := #file

	bin_modif, bok := get_file_last_modified(binary_path, allocator)
	src_modif, sok := get_file_last_modified(source_path, allocator)
	if !bok || !sok {
		log.errorf("Could not auto rebuild, failed to get last modified time of binary or source path.")
		return true
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

get_files_in_dir_handle :: proc(wd_handle: os.Handle, max_num_files := 10, allocator := context.temp_allocator) -> (files: []os.File_Info, ok: bool) {
	fs, ferr := os.read_dir(wd_handle, max_num_files, allocator = allocator)
	if ferr != nil {
		log.errorf("Failed to read current directory: %v", ferr)
		return
	}
	return fs, true
}

get_files_in_dir_path :: proc(path: string, max_num_files := 10, allocator := context.temp_allocator) -> (files: []os.File_Info, ok: bool) {
	wd_handle, err := os.open(path)

	defer close_file(wd_handle)

	if err != nil {
		log.errorf("Failed to open current directory: %v", err)
		return
	}
	return get_files_in_dir_handle(wd_handle, max_num_files, allocator)
}

get_files_in_dir :: proc{get_files_in_dir_handle, get_files_in_dir_path}

make_or_open_file :: proc(path: string) -> (os.Handle, bool) {
	f: os.Handle
	err: os.Error
	if os.exists(path) {
		f, err = os.open(path, os.O_WRONLY, os.S_IWGRP | os.S_IWUSR | os.S_IWOTH | os.S_IRUSR | os.S_IRGRP | os.S_IROTH)
	}
	else {
		f, err = os.open(path, os.O_WRONLY | os.O_CREATE, os.S_IWGRP | os.S_IWUSR | os.S_IWOTH | os.S_IRUSR | os.S_IRGRP | os.S_IROTH)
	}

	if err != nil {
		log.errorf("Failed to create/open file: %s", os.error_string(err))
		return {}, false
	}

	return f, true
}

open_file :: proc(path: string) -> (os.Handle, bool) {
	f: os.Handle
	err: os.Error
	if os.exists(path) {
		f, err = os.open(path, os.O_RDWR)
	}
	else {
		log.errorf("File '%s' does not exist.")
		return {}, false
	}

	if err != nil {
		log.errorf("Failed to open file: %s", os.error_string(err))
		return {}, false
	}

	return f, true
}

close_file :: proc(handle: os.Handle) {
	os.close(handle)
}

import "core:flags"

Build_Mode :: enum {
	// default (ZII is so babygirl <3)
	build = 0,
	check,
	run,
	just_run,
	// for debugging build script or asset gen, doesn't run anything
	dry,
}

Cmd_Options :: struct {
	// ggdb debug symbols in final binary
	debug: bool,
	// unused variables is error
	vet: bool,
	// re-compile assets
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
		log.error("Error parsing command line options: vvv")
		flags.print_errors(Cmd_Options, err, os.args[0])
		// log.fatalf(": %v", err)
		return
	}

	if !make_dir("./bin") do return
	c: Command

	if opts.mode == .just_run {
		files, ok := get_files_in_dir("."); assert(ok)
		for f in files {
			if f.name == "bin" {
				files, ok = get_files_in_dir("./bin")
				if len(files) == 0 do break

				filename: string
				if opts.debug {
					for file in files {
						if file.name == "debug" {
							filename = "debug"
						}
					}
				}
				else {
					for file in files {
						if file.name == "main" {
							filename = "main"
						}
					}
				}

				if filename == "" do break

				command_append(&c, fmt.tprintf("./bin/%s", filename))

				if opts.mode != .dry do command_run(&c)

				return
			}
		}

		log.errorf("No existing binary found matching the provided arguments, use 'run' to build and run.")
		return
	}

	command_append(&c, "odin")
	switch opts.mode {
	case .run:
		command_append(&c, "run")
	case .check:
		command_append(&c, "check")
	case .build:
		command_append(&c, "build")
	case .just_run:
		unreachable()
	case .dry:
	}
	command_append(&c, "src")

	vets : []string = {"-vet-using-stmt", "-vet-using-param", "-vet-style", "-vet-cast"}
	command_append(&c, ..vets)

	// this is entirely for me, for documentation purposes
	flags : []string = {"-custom-attribute:interface"}
	command_append(&c, ..flags)

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

		files, fok := get_files_in_dir("./assets/")
		if !fok {
			log.errorf("Could not find assets folder, as such could not generate assets.")
		}
		for file in files {
			if file.is_dir {
				log.infof("Contents of '%s':\n", file.name)
				inner := get_files_in_dir(file.fullpath) or_continue
				for i in inner {
					log.info(i.name)
				}
				log.info("\n")
			}
		}

		if !make_dir("./__gen") do log.panicf("Could not create __gen folder")
		h, gok := make_or_open_file("./__gen/assets.odin")
		if !gok do log.panicf("Could not open file __gen/assets.odin")
		defer close_file(h)

		sb := strings.builder_make(allocator = context.temp_allocator)
		strings.write_string(&sb, fmt.tprintf("// AUTOMATICALLY GENERATED BY %s (line %v) -- DO NOT MODIFY!\n", #file, #line))
		strings.write_string(&sb, "package gen\n")

		strings.write_string(&sb, "\n\n")
		strings.write_string(&sb, "Asset :: enum {\n")


		s := strings.to_string(sb)
		fmt.println(s)
		// os.write_string(h, s)
		// command_append(&c, "-define:__GEN_ASSETS__=true")
	}

	if opts.mode != .dry do command_run(&c)
}