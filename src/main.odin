package main;

import rl "thirdparty/raylib";
import rlgl "thirdparty/raylib/rlgl"
import "core:math";
import "core:fmt";
import "core:mem";

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

debug_print: bool = false;
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
		scale.x * camera.zoom, scale.y * camera.zoom,
	};
	origin := transmute(rl.Vector2) Vec2{};// scale / 2;
	rl.DrawRectanglePro(rec, origin, rot, transmute(rl.Color) col);
}

main :: proc() {	
	when DEBUG do initialise_debugging();

	fmt.println(linalg.normalize(Vec2(0)))

	initialise_camera();

	// TODO: make this not a global?
	initialise_resources();
	defer free_resources();

	initialise_phys_world();
	defer free_phys_world();

	initialise_timers();
	defer free_timers();

	rl.InitWindow(window_width, window_height, "yeah")
	rl.SetTargetFPS(60)
	// Note: neccessary so that sprites flipped by portal travel get rendered
	rlgl.DisableBackfaceCulling()
	rl.SetWindowState({.WINDOW_RESIZABLE})

	five_w, ok := load_texture("5W.png")
	if !ok do os.exit(1)

	dir_tex: Texture_Id
	dir_tex, ok = load_texture("nesw_sprite.png")
	if !ok do os.exit(1)

	test_map, tmap_ok := load_tilemap("second_map.tmx");
	if !tmap_ok do os.exit(1);
	generate_static_physics_for_tilemap(test_map, 0);

	initialise_portal_handler();
	defer free_portal_handler();

	player: Player = player_new(dir_tex);

	portal_handler.portals.x.state += {.Alive};
	portal_handler.portals.y.state += {.Alive};

	// --------- DEVELOPMENT VARIABLES -- REMOVE THESE --------- 

	when DEBUG {
		debug_mode := false
	}

	run_physics := true

	test_obj := add_phys_object_aabb(
		pos = get_screen_centre(), 
		scale = Vec2{40, 40}, 
		mass = kg(10), 
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

	collision: rl.RayCollision

	target: Vec3
	spin: f32

	// --------- DEVELOPMENT VARIABLES -- REMOVE THESE --------- 

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime();

		rl.BeginDrawing();
		rl.ClearBackground(rl.GetColor(BACKGROUND_COLOUR));
		rl.DrawFPS(0, 0);

		player_obj:=phys_obj(player.obj);

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
		draw_phys_obj(test_obj, texture=dir_tex, colour=Colour(255));
		// ------------   END   ------------

		// ------------ UPDATING ------------
		if run_physics || rl.IsKeyPressed(rl.KeyboardKey.U) do update_phys_world(dt);
		if rl.IsKeyPressed(rl.KeyboardKey.P) do run_physics = !run_physics
		// update_portals(test_obj);
		update_portals(player.obj)
		update_timers(dt)
		update_player(&player, dt)

		when DEBUG do update_debugging(dt);
		// ------------    END   ------------

		// vvvvvv <- random testing stuff ahead

		spin += 1 * dt
		target = Vec3 { math.cos(spin), math.sin(spin), 0 }
		draw_line(Vec2(0), target.xy * 50, Colour(255))

		// mat := 
		// 	linalg.matrix3_look_at_f32(Vec3(0), target, Z_AXIS)
		// quat := linalg.quaternion_from_matrix3_f32(mat)
		quat := linalg.quaternion_look_at(Vec3(0), target, Z_AXIS)
		// facing := linalg.yaw_from_quaternion(quat)
		x, y, z := linalg.euler_angles_xyz_from_quaternion(quat)
		facing := -z + linalg.PI/2
		draw_line(Vec2(0), Vec2 { math.cos(facing), math.sin(facing) } * 100, Colour{2..<4 = 255})
		// draw_line(Vec2(0), Vec2{mat[0, 0], mat[0, 1]} * 100, Colour{3=255, 2=255})

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
		rotate(portal_obj, Rad(rotate_dir * math.PI/2));
		if rl.IsKeyPressed(rl.KeyboardKey.LEFT_ALT) do selected_portal = 1 - selected_portal;

		if rl.IsKeyPressed(rl.KeyboardKey.LEFT_CONTROL) do follow_player = true;

		if !dragging && selected == -1 && follow_player {
			delta := 0.01 * ((player_obj.pos - get_screen_centre()) * camera.zoom - camera.pos)
			camera.pos += 0.01 * ((player_obj.pos - get_screen_centre()) * camera.zoom - camera.pos);
		}

		

		if rl.IsMouseButtonPressed(rl.MouseButton.MIDDLE) {
			pointer = get_world_mouse_pos();
		}
		else if rl.IsKeyPressed(rl.KeyboardKey.C) do pointer = get_world_screen_centre();
		draw_texture(five_w, pointer, drawn_portion = Rect { 100, 100, 100, 100 }, scale = {0.05, 0.05});

		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
			hit: bool
			collision, hit = cast_ray_in_world(
				player_obj.pos, 
				linalg.normalize(get_world_mouse_pos() - phys_obj_world_pos(player_obj)),
				layers = {.Portal_Surface}
			)
			if hit {
				prtl_obj := phys_obj(portal_handler.portals[selected_portal].obj)
				og := Vec3{collision.point.x, collision.point.y, 0}
				pt := og + Vec3{collision.normal.x, collision.normal.y, 0}
				quat := linalg.quaternion_look_at(og, pt, Z_AXIS)

				// facing := linalg.yaw_from_quaternion(quat)
				x, y, z := linalg.euler_angles_xyz_from_quaternion(quat)
				facing := z + linalg.PI/2
				setrot(prtl_obj, Rad(facing))
				prtl_obj.local = transform_flip(prtl_obj)
				// prtl_obj.local.mat =
				// 	linalg.matrix4_look_at_f32(og, og + pt * 10, Z_AXIS)
				// transform_reset_rotation_plane(prtl_obj)
				// transform_update(portal_obj)
				setpos(prtl_obj, collision.point.xy)
			}
		}
		if collision.hit {
			draw_line(collision.point.xy, collision.point.xy + collision.normal.xy * 100, Colour{1 = 255, 3 = 255})
		}
		// setrot(phys_obj(portal_handler.portals[selected_portal].obj), Rad(-spin))


when DEBUG {
		if rl.IsKeyPressed(rl.KeyboardKey.J) do debug_mode = !debug_mode

		if debug_mode {
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

			mouse_move := rl.GetMouseWheelMove();
			if mouse_move != 0 {
				camera.zoom += mouse_move * 0.1;
			}

			if rl.IsKeyPressed(rl.KeyboardKey.B) do debug_toggle()
		}

} // when DEBUG
		
		rl.EndDrawing();
	}

	rl.CloseWindow();
}
