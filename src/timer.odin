package main;

import "core:log";

Timer_Flags :: enum {
	Update_Automatically,
	Finished,
	Repeating,
	Just_Finished,
}

NUM_UNNAMED_TIMERS :: 128;

Timer_Handler :: struct #no_copy {
	unnamed: [NUM_UNNAMED_TIMERS]Timer,
	timer_index: int,
	named: map[string]Timer,
	initialised: bool,
}

Timer :: struct {
	duration, current: f32,
	flags: bit_set[Timer_Flags],
}

timer_new :: proc(duration: f32, current := f32(0), flags : bit_set[Timer_Flags] = {}) -> Timer {
	return Timer {
		duration = duration,
		current = current,
		flags = flags,
	}
}

initialise_timers :: proc() {
	timers.named = make(map[string]Timer);
	timers.timer_index = 0;
	timers.initialised = true;
}

free_timers :: proc() {
	delete(timers.named); 
}

update_timers :: proc(dt: f32) {
	for &timer in timers.unnamed {
		if .Update_Automatically in timer.flags 	do update_timer(&timer, dt);
	}
	for _, &timer in timers.named {
		if .Update_Automatically in timer.flags 	do update_timer(&timer, dt);
	}
}

get_named_timer :: proc(name: string) -> ^Timer {
	if name not_in timers.named do log.panicf("a named timer was not found: %s", name);

	return &timers.named[name];
}

create_named_timer :: proc(name: string, duration: f32, current: f32 = 0, flags: bit_set[Timer_Flags] = {}) -> ^Timer {
	if name in timers.named do return &timers.named[name];

	timers.named[name] = Timer { duration = duration, current = current, flags = flags };
	return &timers.named[name];
}

get_temp_timer :: proc(duration: f32, current: f32 = 0, flags: bit_set[Timer_Flags] = {}) -> ^Timer {
	if timers.timer_index >= NUM_UNNAMED_TIMERS {
		log.warn("[WARNING]: Overflowed temp timers");
		timers.timer_index = 0;
	}
	timers.timer_index += 1;
	timers.unnamed[timers.timer_index] = Timer { duration = duration, current = current, flags = flags };
	return &timers.unnamed[timers.timer_index];
}

// from 0..=1
ref_timer_fraction :: proc(timer: ^Timer) -> f32 {
	return timer.current / timer.duration;
}

named_timer_fraction :: proc(name: string) -> f32 {
	if name not_in timers.named do log.panicf("a named timer was not found: %s", name);

	return ref_timer_fraction(&timers.named[name])
}

timer_fraction :: proc{ref_timer_fraction, named_timer_fraction};

ref_reset_timer :: proc(timer: ^Timer) {
	timer.current = 0;
	timer.flags -= {.Finished, .Just_Finished};
}

ref_is_timer_done :: proc(timer: ^Timer) -> bool {
	return .Finished in timer.flags || .Just_Finished in timer.flags;
}

ref_is_timer_just_done :: proc(timer: ^Timer) -> bool {
	return .Just_Finished in timer.flags;
}

ref_update_timer :: proc(timer: ^Timer, dt: f32) {
	if is_timer_done(timer) {
		if .Repeating in timer.flags {
			reset_timer(timer);
		}
		if .Just_Finished in timer.flags do timer.flags -= {.Just_Finished};
	} 
	else {
		timer.current += dt;
		if timer.current >= timer.duration do timer.flags += {.Finished, .Just_Finished};
	}
}

ref_set_timer_done :: proc(timer: ^Timer) {
	timer.flags += {.Finished};
}

named_reset_timer :: proc(name: string) {
	if name not_in timers.named do log.panicf("a named timer was not found: %s", name);

	ref_reset_timer(&timers.named[name])
}
named_is_timer_done :: proc(name: string) -> bool {
	if name not_in timers.named do log.panicf("a named timer was not found: %s", name);

	return ref_is_timer_done(&timers.named[name])
}
named_is_timer_just_done :: proc(name: string) -> bool {
	if name not_in timers.named do log.panicf("a named timer was not found: %s", name);

	return ref_is_timer_just_done(&timers.named[name])
}
named_update_timer :: proc(name: string, dt: f32) {
	if name not_in timers.named do log.panicf("a named timer was not found: %s", name);

	ref_update_timer(&timers.named[name], dt)
}
named_set_timer_done :: proc(name: string) {
	if name not_in timers.named do log.panicf("a named timer was not found: %s", name);

	ref_set_timer_done(&timers.named[name])
}

reset_timer :: proc{ref_reset_timer, named_reset_timer};
is_timer_done :: proc{ref_is_timer_done, named_is_timer_done};
is_timer_just_done :: proc{ref_is_timer_just_done, named_is_timer_just_done};
update_timer :: proc{ref_update_timer, named_update_timer};
set_timer_done :: proc{ref_set_timer_done, named_set_timer_done};

drop_temp_timers :: proc() {
	timers.timer_index = 0;
}