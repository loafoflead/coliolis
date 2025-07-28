package main;

import rl "thirdparty/raylib";
import "core:math";
import "core:fmt";
import "core:mem";

import "core:math/ease";
import "core:math/linalg";

import "core:os";

import "tiled";

// -------------- GLOBALS --------------
camera 		: Camera2D;
resources 	: Resources;
phys_world  : Physics_World;
timers  	: Timer_Handler;
portal_handler 	: Portal_Handler;

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
	origin := transmute(rl.Vector2) Vec2{};// scale / 2;
	rl.DrawRectanglePro(rec, origin, rot, transmute(rl.Color) col);
}

main :: proc() {	
	initialise_camera();

	// TODO: make this not a global?
	initialise_resources();
	defer free_resources();

	initialise_phys_world();
	defer free_phys_world();

	initialise_timers();
	defer free_timers();

	rl.InitWindow(window_width, window_height, "yeah");

	five_w, ok := load_texture("5W.png");
	if !ok do os.exit(1);

	test_map, tmap_ok := load_tilemap("second_map.tmx");
	if !tmap_ok do os.exit(1);
	generate_static_physics_for_tilemap(test_map, 0);

	initialise_portal_handler();
	defer free_portal_handler();

	player: Player = player_new(five_w);

	portal_handler.portals.x.state += {.Alive};
	portal_handler.portals.y.state += {.Alive};

	in_air: bool;
	jump_timer := get_temp_timer(0.2);
	jumping: bool;
	coyote_timer := get_temp_timer(0.25);

	player_step_target: Vec2;
	player_step_origin: Vec2;
	player_step_timer := get_temp_timer(0.2);
	set_timer_done(player_step_timer);

	// --------- DEVELOPMENT VARIABLES -- REMOVE THESE --------- 

	test_obj := add_phys_object_aabb(
		pos = get_screen_centre(), 
		scale = Vec2{40, 40}, 
		mass = kg(1), 
		flags={.No_Gravity}
	); 
	// test object

	a := add_phys_object_aabb(scale=Vec2(40), flags= {.Non_Kinematic, .No_Gravity}, collision_layers = {.Trigger});
	papi := &phys_obj(a).local;
	b := add_phys_object_aabb(pos=Vec2(50), scale=Vec2(40), parent=papi, flags= {.Non_Kinematic, .No_Gravity}, collision_layers = {.Trigger});

	follow_player: bool = true;

	mouse_last_pos: Vec2;
	selected: Physics_Object_Id = -1;
	og_flags: bit_set[Physics_Object_Flag];

	dragging: bool;
	drag_og: Vec2;

	pointer : Vec2;

	selected_portal: int = 0;

	debug_timer := create_named_timer("debug", 1.0, flags={.Update_Automatically, .Repeating});

	// --------- DEVELOPMENT VARIABLES -- REMOVE THESE --------- 

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime();

		rl.BeginDrawing();
		rl.ClearBackground(rl.GetColor(BACKGROUND_COLOUR));

		player_obj:=phys_obj(player.obj);

		if is_timer_done(debug_timer) {
			// debug printing here
		}

		// draw_hitbox_at(player_obj.pos, &player_obj.hitbox);
		// for i in 0..<len(phys_world.objects) {
		// 	draw_phys_obj(i);
		// }

		// an_obj := phys_obj(a);
		// bb := phys_obj_bounding_box(an_obj);
		// draw_rectangle(bb.xy, bb.zw, col=Colour{100, 0, 0, 255});
		// draw_rectangle_transform(an_obj, phys_obj_to_rect(an_obj));

		// ------------ DRAWING ------------
		draw_tilemap(test_map, {0., 0.});
		draw_portals(selected_portal);
		draw_player(&player);

		// draw_phys_obj(a);
		// draw_phys_obj(b);
		draw_phys_obj(test_obj);
		// ------------   END   ------------

		// ------------ UPDATING ------------
		update_phys_world(dt);
		// update_portals(test_obj);
		update_portals(player.obj);
		update_timers(dt);
		// ------------    END   ------------

		// vvvvvv <- random testing stuff ahead

		phys_obj(a).rot += 1 * dt;

		rotate_dir: f32;
		portal_obj := phys_obj(portal_handler.portals[selected_portal].obj);
		if rl.IsKeyPressed(rl.KeyboardKey.LEFT) {
			rotate_dir = 1;
		}
		else if rl.IsKeyPressed(rl.KeyboardKey.RIGHT) {
			rotate_dir = -1;
		}
		else do rotate_dir = 0;

		if rl.IsKeyPressed(rl.KeyboardKey.F) {
			portal_obj.local = transform_flip(portal_obj);
		}
		rotate(portal_obj, rotate_dir * math.PI/2);
		if rl.IsKeyPressed(rl.KeyboardKey.LEFT_ALT) do selected_portal = 1 - selected_portal;

		if rl.IsKeyPressed(rl.KeyboardKey.LEFT_CONTROL) do follow_player = true;

		if !dragging && selected == -1 && follow_player {
			camera.pos += 0.01 * ((player_obj.pos - get_screen_centre()) - camera.pos);
		}

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
				player_obj.vel.y = -PLAYER_JUMP_STR * (1 - ease.exponential_out(jump_timer.current));
				update_timer(jump_timer, dt);
			}
		}
		else {
			jumping = false;
		}

		if phys_obj_grounded(player.obj) {
			in_air = false;
			reset_timer(jump_timer);
			reset_timer(coyote_timer);
		}
		else {
			update_timer(coyote_timer, dt);
			in_air = true;
		}


		if move != 0.0 && is_timer_done(player_step_timer) {
			dir := Vec2 { move, 0 };
			ahead_of_feet := player_feet(&player) + dir * 20;
			ahead_of_knees := player_feet(&player) + -Y_AXIS.xy * PLAYER_STEP_UP_HEIGHT + dir * 20;
			draw_line(player_feet(&player), ahead_of_feet, Colour{255, 0, 0, 255});
			draw_line(player_feet(&player), ahead_of_knees, Colour{0, 0, 255, 255});
			_, _, hit_feet := point_collides_in_world(ahead_of_feet, layers = {.Default, .L0});
			_, _, too_high := point_collides_in_world(ahead_of_knees, layers = {.Default, .L0});
			if hit_feet && !too_high {
				// og := player_obj.pos + dir * 20;
				draw_line(player_obj.pos, ahead_of_knees, Colour{0, 255, 0, 255});

				col, hit := cast_ray_in_world(ahead_of_knees, Y_AXIS.xy);
				if hit && col.distance > 1 {
					reset_timer(player_step_timer);
					player_step_origin = player_obj.pos;
					player_step_target = (transmute(Vec3) col.point).xy - Vec2{0, phys_obj_to_rect(player_obj).w/2};
				}
			}
		}

		if move != 0.0 && is_timer_done(player_step_timer) {
			player_obj.acc.x = move * PLAYER_HORIZ_ACCEL;
		}
		else {
			player_obj.acc.x = 0.0;	
		}

		if !is_timer_done(player_step_timer) {
			player_obj.pos = player_step_origin + (player_step_target - player_step_origin) * ease.ease(ease.Ease.Circular_In, timer_fraction(player_step_timer)); 
			update_timer(player_step_timer, dt);
		}

		if rl.IsKeyDown(rl.KeyboardKey.G) {
			rotate(player_obj, 0.01);
		}
		else if rl.IsKeyDown(rl.KeyboardKey.H) {
			rotate(player_obj, -0.01);
		}
		else {
			if math.abs(player_obj.rot) > 0.3 {
				// rotate(player_obj, player_obj.rot * 0.01);
				rotate(player_obj, player_obj.rot * -0.05);
			}
			else {
				player_obj.local = transform_new(player_obj.pos, 0);
				// setrot(player_obj, 0);
			}
			// if player_obj.rot < 0 && player_obj.rot > -linalg.PI {
			// 	rotate(player_obj, player_obj.rot * 0.01);
			// }
			// else if player_obj.rot > 0 && player_obj.rot < linalg.PI {
			// 	rotate(player_obj, -player_obj.rot * 0.01);
			// }
		}
		// player.obj.vel += move * PLAYER_SPEED * dt;

		if rl.IsMouseButtonPressed(rl.MouseButton.MIDDLE) {
			pointer = get_world_mouse_pos();
		}
		draw_texture(five_w, pointer, drawn_portion = Rect { 100, 100, 100, 100 }, scale = {0.05, 0.05});

		selected_obj, any_selected := phys_obj(selected);
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && dragging == false {
			obj, obj_id, ok := point_collides_in_world(get_world_mouse_pos());
			if ok && .Fixed not_in obj.flags {
				og_flags = obj.flags;
				obj.flags |= {.Non_Kinematic, .Fixed};
				selected = obj_id;
			}
		}
		if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) && any_selected {
			selected_obj.flags = og_flags;
			selected_obj.vel = (get_world_mouse_pos() - mouse_last_pos) * 100;
			// selected.flags ~= u32(Physics_Object_Flag.Non_Kinematic);
			selected = -1;
		}
		if any_selected {
			// FIXME: doesn't work with parent transforms
			setpos(selected_obj, get_world_mouse_pos());
			mouse_last_pos = get_world_mouse_pos();
		}

		if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) && !any_selected && dragging == false {
			dragging = true;
			drag_og = camera.pos + get_mouse_pos();
			follow_player = false;
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