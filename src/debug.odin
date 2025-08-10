package main;

import "core:fmt"

DEBUG :: true
DEBUG_TIMER_DURATION := f32(1) // seconds
Debug_State :: struct {
	debug_timer: Timer,
	print_continuous: bool,
}
when DEBUG {
	debug_state := Debug_State {
		print_continuous = false,
		debug_timer = Timer {duration = DEBUG_TIMER_DURATION, flags = {.Repeating}},
	}
	

	initialise_debugging :: proc() {}

	update_debugging :: proc(dt: f32) {
		update_timer(&debug_state.debug_timer, dt)
	}

	debug_toggle :: proc() {
		debug_state.print_continuous = !debug_state.print_continuous
	}

	debug_log :: proc(msg: string, args: ..any, timed := true) {
		when !DEBUG do return;

		if debug_state.print_continuous {
			fmt.printfln(msg, ..args)
		}
		else if timed {
			if is_timer_done(&debug_state.debug_timer) do fmt.printfln(msg, ..args)
		}
		else if !timed {
			fmt.printfln(msg, ..args)
		}
	}
}
else {
	debug_log :: proc(_: ..any){}
}