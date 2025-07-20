package main;

import rl "thirdparty/raylib";
import "core:math";
import "core:fmt";

import "core:os";

import "tiled";

// -------------- GLOBALS --------------
camera 		: Camera2D;
resources 	: Resources;
phys_world  : Physics_World;
timers  	: Timer_Handler;
portals 	: Portal_Handler;

window_width : i32 = 600;
window_height : i32 = 400;
// --------------   END   --------------

BACKGROUND_COLOUR :: 0x181818;

get_screen_centre :: proc() -> Vec2 {
	return Vec2 { cast(f32) rl.GetScreenWidth() / 2.0, cast(f32) rl.GetScreenHeight() / 2.0 };
}

get_mouse_pos :: proc() -> Vec2 {
	return Vec2 { cast(f32) rl.GetMouseX(), cast(f32) rl.GetMouseY() };
}

Vec2 :: [2]f32;
Rect :: [4]f32;
Colour :: [4]u8;

ZERO_VEC2 :: Vec2{0,0};
MARKER_VEC2 :: Vec2 { math.F32_MAX, math.F32_MAX };
MARKER_RECT :: Rect { math.F32_MAX, math.F32_MAX, math.F32_MAX, math.F32_MAX };



calculate_terminal_velocity :: proc(gravity, mass, drag: f32) -> f32 {
	return math.sqrt((gravity * mass) / drag);
}

kg :: proc(num: f32) -> f32 {
	return num * 1000.0;
}

draw_rectangle :: proc(pos, scale: Vec2, rot: f32 = 0.0, col: Colour = cast(Colour) rl.RED) {
	screen_pos := world_pos_to_screen_pos(camera, pos);
	rec := rl.Rectangle {
		screen_pos.x, screen_pos.y,
		scale.x, scale.y,
	};
	origin := rl.Vector2{};
	rl.DrawRectanglePro(rec, origin, rot, transmute(rl.Color) col);
}

Portal :: enum {
	Pete,
	Leth,
}

Portal_Handler :: struct {
	pete_obj, leth_obj: ^Physics_Object,
	active: bit_set[Portal],
}

initialise_portals :: proc() {
	if !phys_world.initialised do return;

	portals.pete_obj, _ = add_phys_object_aabb(
		scale = Vec2 { 80.0, 20.0 },
		flags = {.Trigger}, 
	);
	portals.leth_obj, _ = add_phys_object_aabb(
		scale = Vec2 { 80.0, 20.0 },
		flags = {.Trigger}, 
	);
}
free_portals :: proc() {}

draw_portal :: proc(portal: Portal) {
	colour: Colour;
	switch portal {
	case .Pete:
		colour=Colour{0, 255, 0, 255};
		draw_rectangle(portals.pete_obj.pos, portals.pete_obj.hitbox, rot=portals.pete_obj.rot, col=colour);
	case .Leth:
		colour=Colour{0, 0, 255, 255};
		draw_rectangle(portals.pete_obj.pos, portals.pete_obj.hitbox, rot=portals.pete_obj.rot, col=colour);
	}
}

draw_portals :: proc() {
	if portals.active == {} {
		return;
	}

	if .Leth in portals.active do draw_portal(.Leth);
	if .Pete in portals.active do draw_portal(.Pete);
}

main :: proc() {	
	initialise_camera();

	initialise_resources();
	defer free_resources();

	initialise_phys_world();
	defer free_phys_world();

	initialise_timers();
	defer free_timers();

	initialise_portals();
	defer free_portals();

	rl.InitWindow(window_width, window_height, "yeah");

	five_w, ok := load_texture("5W.png");
	if !ok do os.exit(1);
	
	test_map, tmap_ok := load_tilemap("second_map.tmx");
	if !tmap_ok do os.exit(1);
	generate_static_physics_for_tilemap(test_map, 0);

	player: Player;
	player.obj, player.obj_id = add_phys_object_aabb(
		pos = get_screen_centre(), 
		mass = kg(1.0), 
		scale = Vec2 { 30.0, 30.0 },
		flags = {.Drag_Exception}, 
	);
	fmt.println(calculate_terminal_velocity(EARTH_GRAVITY, player.obj.mass, ARBITRARY_DRAG_COEFFICIENT));

	selected: ^Physics_Object;
	og_flags: bit_set[Physics_Object_Flag];

	dragging: bool;
	drag_og: Vec2;

	pointer : Vec2;

	in_air: bool;
	jump_timer := get_temp_timer(0.2);
	jumping: bool;
	coyote_timer := get_temp_timer(0.25);

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime();
		rl.BeginDrawing();
		rl.ClearBackground(rl.GetColor(BACKGROUND_COLOUR));

		draw_tilemap(test_map, {0., 0.});
		draw_hitbox_at(player.obj.pos, &player.obj.hitbox);
		draw_portals();
		// for &obj in phys_world.objects {
		// 	draw_hitbox_at(obj.pos, &obj.hitbox);
		// }
		// camera.pos += Vec2 {10.0, 10.0} * dt;
		update_phys_world(dt);
		update_timers(dt);
		camera.pos = player.obj.pos - get_screen_centre();

		move: f32 = 0.0;
		if rl.IsKeyDown(rl.KeyboardKey.D) {
			move +=  1;
		}
		if rl.IsKeyDown(rl.KeyboardKey.A) {
			move += -1;
		}

		if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			if !in_air || !is_timer_done(coyote_timer) {
				jumping = true;
				if !is_timer_done(coyote_timer) do set_timer_done(coyote_timer);
			}
		}
		if rl.IsKeyDown(rl.KeyboardKey.SPACE) {
			if jumping && !is_timer_done(jump_timer) {
				player.obj.vel.y = -PLAYER_JUMP_STR * (1 - ease_out_expo(jump_timer.current));
				update_timer(jump_timer, dt);
			}
		}
		else {
			jumping = false;
		}

		if phys_obj_grounded(player.obj_id) {
			in_air = false;
			reset_timer(jump_timer);
			reset_timer(coyote_timer);
		}
		else {
			update_timer(coyote_timer, dt);
			in_air = true;
		}
		// if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
		// 	if !jumping && jump_timer == 0.0 do jumping = true;
		// }

		// if rl.IsKeyReleased(rl.KeyboardKey.SPACE) && jumping {
		// 	jumping = false;
		// }

		// if rl.IsKeyDown(rl.KeyboardKey.SPACE) {
		// 	if jumping {
		// 		player.obj.acc.y = -PLAYER_JUMP_STR * (1 - ease_out_expo(jump_timer));
		// 		fmt.println((1 - ease_out_expo(jump_timer)));
		// 		jump_timer += dt;
		// 	}
		// 	if jump_timer >= 1.0 do wants_to_jump = true;
		// }
		// else {
		// 	wants_to_jump = false;
		// }

		// if jump_timer >= 0.0 &&  {
		// 	jump_timer = 0;
		// 	if wants_to_jump do jumping = true;
		// }
		// else if jump_timer >= 1.0 do jumping = false;

		if move != 0.0 {
			player.obj.acc.x = move * PLAYER_HORIZ_ACCEL;
		}
		else {
			player.obj.acc.x = 0.0;
		}
		// player.obj.vel += move * PLAYER_SPEED * dt;

		if rl.IsMouseButtonPressed(rl.MouseButton.MIDDLE) {
			pointer = get_world_mouse_pos();
		}
		draw_texture(five_w, pointer, drawn_portion = Rect { 100, 100, 100, 100 }, scale = {0.1, 0.1});

		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && dragging == false {
			for &obj in phys_world.objects {
				if rl.CheckCollisionPointRec(
					transmute(rl.Vector2) get_world_mouse_pos(), 
					transmute(rl.Rectangle) phys_obj_to_rect(&obj)
				) {
					og_flags = obj.flags;
					obj.flags |= {.Non_Kinematic};
					selected = &obj;
					break; // if hovering multiple objects, tant pis
				}
			}
		}
		if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) && selected != nil {
			selected.flags = og_flags;
			// selected.flags ~= u32(Physics_Object_Flag.Non_Kinematic);
			selected = nil;
		}
		if selected != nil {
			selected.pos = get_world_mouse_pos() - selected.hitbox / 2.0;
		}

		if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) && selected == nil && dragging == false {
			dragging = true;
			drag_og = camera.pos + get_mouse_pos();
		}
		if rl.IsMouseButtonReleased(rl.MouseButton.RIGHT) {
			dragging = false;
		}
		if dragging {
			camera.pos = drag_og - get_mouse_pos();
		}
		
		rl.EndDrawing();
	}

	rl.CloseWindow();
}