package main;

import "core:fmt";

Timer_Flags :: enum {
	Update_Automatically,
	Finished,
}

NUM_UNNAMED_TIMERS :: 16;

Timer_Handler :: struct {
	unnamed: [NUM_UNNAMED_TIMERS]Timer,
	timer_index: int,
	named: map[string]Timer,
}

Timer :: struct {
	duration, current: f32,
	flags: bit_set[Timer_Flags],
}

initialise_timers :: proc() {
	timers.named = make(map[string]Timer);
	timers.timer_index = 0;
}

free_timers :: proc() {
	delete(timers.named); 
}

update_timers :: proc(dt: f32) {
	for &timer in timers.unnamed {
		if .Finished in timer.flags 				do continue;
		if .Update_Automatically in timer.flags 	do update_timer(&timer, dt);
	}
	for _, &timer in timers.named {
		if .Finished in timer.flags 				do continue;
		if .Update_Automatically in timer.flags 	do update_timer(&timer, dt);
	}
}

create_named_timer :: proc(name: string, duration: f32, current: f32 = 0, flags: bit_set[Timer_Flags] = {}) -> ^Timer {
	if name in timers.named do return &timers.named[name];

	timers.named[name] = Timer { duration = duration, current = current, flags = flags };
	return &timers.named[name];
}

get_temp_timer :: proc(duration: f32, current: f32 = 0, flags: bit_set[Timer_Flags] = {}) -> ^Timer {
	if timers.timer_index >= NUM_UNNAMED_TIMERS {
		fmt.println("[WARNING]: Overflowed temp timers");
		timers.timer_index = 0;
	}
	timers.timer_index += 1;
	timers.unnamed[timers.timer_index] = Timer { duration = duration, current = current, flags = flags };
	return &timers.unnamed[timers.timer_index];
}

reset_timer :: proc(timer: ^Timer) {
	timer.current = 0;
	timer.flags -= {.Finished};
}

is_timer_done :: proc(timer: ^Timer) -> bool {
	return .Finished in timer.flags || timer.current >= timer.duration;
}

update_timer :: proc(timer: ^Timer, dt: f32) {
	if is_timer_done(timer) do return;
	timer.current += dt;
	if timer.current >= timer.duration do timer.flags += {.Finished};
}

drop_temp_timers :: proc() {
	timers.timer_index = 0;
}