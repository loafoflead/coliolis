package main;

import rl "thirdparty/raylib";
import rlgl "thirdparty/raylib/rlgl"
import b2d "thirdparty/box2d"
import "core:math";
import "core:fmt";
import "core:mem";

import "core:math/linalg";

import "core:os";

import "core:log"

import "tiled";

// -------------- GLOBALS --------------
game_state  	: Game_State
camera 			: Camera2D
resources 		: Resources
physics  		: Physics
timers  		: Timer_Handler
portal_handler 	: Portal_Handler

window_width : i32 = 600;
window_height : i32 = 400;

debug_print: bool = false;
// --------------   END   --------------

BACKGROUND_COLOUR :: 0x181818;
TILEMAP :: "portals_intro.tmj"
	// "cube_intro.tmj" 

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

// TODO: GET RID GET RID GET RID OMG
dir_tex: Texture_Id

main :: proc() {

	rl.InitWindow(window_width, window_height, "yeah")
	rl.SetTargetFPS(60)
	// Note: neccessary so that sprites flipped by portal travel get rendered
	rlgl.DisableBackfaceCulling()
	rl.SetWindowState({.WINDOW_RESIZABLE})

	when DEBUG {
		initialise_debugging();
		context.logger = log.create_console_logger() // TODO: free? or not?
	}

	initialise_camera()

	// TODO: make this not a global?
	initialise_resources()
	defer free_resources()

	initialise_phys_world()
	defer free_phys_world()

	initialise_timers();
	defer free_timers();

	initialise_game_state()
	defer free_game_state()

	initialise_portal_handler();
	defer free_portal_handler();

	five_w, ok := load_texture("5W.png")
	if !ok do os.exit(1)

	dir_tex, ok = load_texture("nesw_sprite.png")
	if !ok do os.exit(1)

	game_load_level_from_tilemap(TILEMAP)

	for &p in portal_handler.portals do p.state += {.Alive}

	selected_portal: int

	mouse_last_pos: Vec2;
	mouse_ptr_body_def := b2d.DefaultBodyDef()

	mouse_ptr_body := b2d.CreateBody(physics.world, mouse_ptr_body_def)
	mouse_joint: b2d.JointId

	selected: Maybe(Physics_Object_Id);
	selected_is_static: bool
	og_ty: b2d.BodyType;

	dragging: bool;
	drag_og: Vec2;

	debug_mode: bool = true

	follow_player := false

	collision: Maybe(Ray_Collision)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()


		update_phys_world()
		update_game_state(dt)
		// update_portals();
		update_portals(physics.bodies[1])
		update_timers(dt)



		rl.BeginDrawing()
		rl.ClearBackground(rl.GetColor(BACKGROUND_COLOUR))

		// draw_phys_world()
		draw_portals(selected_portal);
		render_game_objects(camera)
		// draw_texture(dir_tex, pos=rl_to_b2d_pos(get_world_mouse_pos()), scale=0.1)
		draw_tilemap(state_level().tilemap, {0., 0.});

		rl.EndDrawing()


		click: int
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) do click = 1
		else if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) do click = 2

		if click != 0 && click <= game_obj(game_state.player, Player).portals_unlocked {
			player_pos := phys_obj_pos(game_obj(game_state.player, Player).obj)
			col, hit := cast_ray_in_world(
				player_pos,
				player_pos + linalg.normalize(get_world_mouse_pos() - player_pos) * PORTAL_RANGE,
				exclude = {game_obj(game_state.player, Player).obj},
				layers = {.Portal_Surface}
			)
			if hit {
				portal_goto(i32(click), col.point, col.normal)
				collision = col
			}
			else {
				collision = nil
			}
		}
		if col, ok := collision.?; ok {
			draw_line(col.point.xy, col.point.xy + col.normal.xy * 100, Colour{1 = 255, 3 = 255})
			// draw_phys_obj(phys_world.collision_placeholder, colour=Colour{2..<4=255})
		}
		player_pos := phys_obj_pos(game_obj(game_state.player, Player).obj)
		draw_line(player_pos, player_pos + linalg.normalize(get_world_mouse_pos() - player_pos) * 50)

when DEBUG {
		if rl.IsKeyPressed(rl.KeyboardKey.J) do debug_mode = !debug_mode

		if debug_mode {
			selected_id, any_selected := selected.?
			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && dragging == false {
				obj_id, ok := point_collides_in_world(get_world_mouse_pos());
				log.info(obj_id)
				if ok {
					og_ty = b2d.Body_GetType(obj_id)
					if og_ty != b2d.BodyType.staticBody {
						// b2d.Body_SetType(obj_id, b2d.BodyType.dynamicBody)
						selected = obj_id;

						def := b2d.DefaultMouseJointDef()
						def.bodyIdA = mouse_ptr_body
						def.bodyIdB = obj_id
						def.maxForce = 10000000
						def.target = b2d.Body_GetPosition(obj_id)
						def.collideConnected = false

						mouse_joint = b2d.CreateMouseJoint(physics.world, def)
						selected_is_static = false
					}
					else {
						selected_is_static = true
						selected = obj_id
					}
				}
			}
			if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) && any_selected {
				if b2d.Joint_IsValid(mouse_joint) {
					log.info("goop")
					b2d.DestroyJoint(mouse_joint)
					mouse_joint = b2d.nullJointId
				}
				// if !selected_is_static {
					// b2d.Body_SetLinearVelocity(selected_id, (get_world_mouse_pos() - mouse_last_pos) * 100)
				// }

				selected = nil;
			}
			if any_selected {
				mpos := get_b2d_world_mouse_pos()
				if selected_is_static {
					b2d.Body_SetTransform(selected_id, mpos, {1, 0})
				}
				else if b2d.Joint_IsValid(mouse_joint) {
					b2d.MouseJoint_SetTarget(
						mouse_joint,
						rl_to_b2d_pos(get_world_mouse_pos()),
					)
				}
				// b2d.Body_SetTransform(mouse_ptr_body, get_world_mouse_pos(), b2d.Body_GetRotation(mouse_ptr_body))
				mouse_last_pos = get_world_mouse_pos();
			}

			if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) && !any_selected && dragging == false {
				dragging = true;
				drag_og = camera.pos + get_mouse_pos() / camera.zoom;
				follow_player = false;
			}
			if rl.IsMouseButtonReleased(rl.MouseButton.RIGHT) {
				dragging = false;
			}
			if dragging {
				camera.pos = drag_og - (get_mouse_pos() / camera.zoom);
			}

			portal_obj := portal_handler.portals[selected_portal].obj

			mouse_move := rl.GetMouseWheelMove();
			if mouse_move != 0 {
				camera.zoom += mouse_move * 0.1;
			}

			if rl.IsKeyPressed(rl.KeyboardKey.K) do b2d.Body_SetTransform(portal_handler.portals[0].obj, get_b2d_world_mouse_pos(), {1, 0})
			if rl.IsKeyPressed(rl.KeyboardKey.L) do b2d.Body_SetTransform(portal_handler.portals[1].obj, get_b2d_world_mouse_pos(), {1, 0})
			if rl.IsKeyPressed(rl.KeyboardKey.T) do b2d.Body_SetTransform(game_obj(game_state.player, Player).obj, get_b2d_world_mouse_pos(), {1, 0})

			if rl.IsKeyPressed(rl.KeyboardKey.B) do debug_toggle()
		}

} // when DEBUG
	}
}

_ :: proc() {
	
	rl.InitWindow(window_width, window_height, "yeah")
	rl.SetTargetFPS(60)
	// Note: neccessary so that sprites flipped by portal travel get rendered
	rlgl.DisableBackfaceCulling()
	rl.SetWindowState({.WINDOW_RESIZABLE})

	five_w, ok := load_texture("5W.png")
	if !ok do os.exit(1)

	dir_tex, ok = load_texture("nesw_sprite.png")
	if !ok do os.exit(1)

	game_load_level_from_tilemap(TILEMAP)

	// test_gobj := obj_cube_new(get_screen_centre())
	// test_obj := game_obj(test_gobj, Cube).obj

	// portal_handler.portals.x.state += {.Alive};
	// portal_handler.portals.y.state += {.Alive};

	// --------- DEVELOPMENT VARIABLES -- REMOVE THESE --------- 

	when DEBUG {
		debug_mode := false
	}

	run_physics := true

	follow_player: bool = true;

	mouse_last_pos: Vec2;
	selected: Physics_Object_Id;
	og_flags: bit_set[Physics_Object_Flag];

	dragging: bool;
	drag_og: Vec2;

	pointer : Vec2;

	selected_portal: int = 0;

	collision: Ray_Collision

	target: Vec3
	spin: f32

	// --------- DEVELOPMENT VARIABLES -- REMOVE THESE --------- 

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime();

		rl.BeginDrawing();
		rl.ClearBackground(rl.GetColor(BACKGROUND_COLOUR));
		rl.DrawFPS(0, 0);

		player := state_player()

		player_obj:=phys_obj(player.obj);

		// draw_hitbox_at(player_obj.pos, &player_obj.hitbox);
		// for i in 0..<len(phys_world.objects) {
		// 	draw_phys_obj(i);
		// }

		// ------------ DRAWING ------------
		draw_tilemap(state_level().tilemap, {0., 0.});
		draw_portals(selected_portal);
		render_game_objects(camera)

		// draw_phys_obj(test_obj, texture=dir_tex, colour=Colour(255));
		// ------------   END   ------------

		// ------------ UPDATING ------------

		// if run_physics || rl.IsKeyPressed(rl.KeyboardKey.U) do update_phys_world(dt);
		if rl.IsKeyPressed(rl.KeyboardKey.P) do run_physics = !run_physics

		update_game_state(dt)
		// update_portals(test_obj);
		update_portals(player.obj)
		update_timers(dt)

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

		if !dragging && follow_player {
			camera.pos = player_obj.pos
			// delta := 0.05 * ((player_obj.pos - get_screen_centre()) * camera.zoom - camera.pos)
			// camera.pos += delta//0.01 * ((player_obj.pos - get_screen_centre()) * camera.zoom - camera.pos);
		}

		if rl.IsWindowResized() {
			window_width = rl.GetScreenWidth()
			window_height = rl.GetScreenHeight()
			camera.scale = Vec2{cast(f32)window_width, cast(f32)window_height}
		}
		

		// if rl.IsMouseButtonPressed(rl.MouseButton.MIDDLE) {
		// 	pointer = get_world_mouse_pos();
		// }
		// else if rl.IsKeyPressed(rl.KeyboardKey.C) do pointer = get_world_screen_centre();
		// draw_texture(five_w, pointer, drawn_portion = Rect { 100, 100, 100, 100 }, scale = {0.05, 0.05});

		if rl.IsKeyPressed(rl.KeyboardKey.C) {
			obj_cube_new(get_world_mouse_pos())
		}

		click: int
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) do click = 1
		else if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) do click = 2

		if click != 0 && click <= player.portals_unlocked {
			hit: bool
			collision, hit = cast_ray_in_world(
				player_obj.pos, 
				linalg.normalize(get_world_mouse_pos() - phys_obj_world_pos(player_obj)),
				layers = {.Portal_Surface}
			)
			if hit {
				prtl_obj := phys_obj(portal_handler.portals[click - 1].obj)
				og := Vec3{collision.point.x, collision.point.y, 0}
				pt := og + Vec3{collision.normal.x, collision.normal.y, 0}
				quat := linalg.quaternion_look_at(og, pt, Z_AXIS)

				// facing := linalg.yaw_from_quaternion(quat)
				x, y, z := linalg.euler_angles_xyz_from_quaternion(quat)
				facing := z + linalg.PI/2

				obstructed := cast_box_in_world(
					collision.point.xy + collision.normal.xy * (portal_dims().x/2 + 0.5), 
					portal_dims(), 
					Rad(facing),
					exclude = {player.obj},
					layers = {.Default},
				)
				if !obstructed {
					setrot(prtl_obj, Rad(facing))
					if collision.normal.x == 0 {
						if collision.normal.y < 0 {
							rotate(prtl_obj, Rad(linalg.PI))
						} else {
							prtl_obj.local = transform_flip(prtl_obj)
						}
					}
					else if collision.normal.x < 0 {
						rotate(prtl_obj, Rad(linalg.PI))
					}
					else {
						prtl_obj.local = transform_flip(prtl_obj)
					}

					portal_handler.portals[click - 1].state += {.Alive}

					// prtl_obj.local.mat =
					// 	linalg.matrix4_look_at_f32(og, og + pt * 10, Z_AXIS)
					// transform_reset_rotation_plane(prtl_obj)
					// transform_update(portal_obj)
					setpos(prtl_obj, collision.point.xy - collision.normal.xy * 8)
				}
			}
		}
		// if collision.hit {
		// 	draw_line(collision.point.xy, collision.point.xy + collision.normal.xy * 100, Colour{1 = 255, 3 = 255})
		// 	// draw_phys_obj(phys_world.collision_placeholder, colour=Colour{2..<4=255})
		// }
		// setrot(phys_obj(portal_handler.portals[selected_portal].obj), Rad(-spin))


// when DEBUG {
// 		if rl.IsKeyPressed(rl.KeyboardKey.J) do debug_mode = !debug_mode

// 		if debug_mode {
// 			selected_obj, any_selected := phys_obj(selected);
// 			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && dragging == false {
// 				obj_id, ok := point_collides_in_world(get_world_mouse_pos());
// 				if ok && .Fixed not_in obj.flags {
// 					og_flags = obj.flags;
// 					obj.flags |= {.Non_Kinematic, .Fixed};
// 					selected = obj_id;
// 				}
// 			}
// 			if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) && any_selected {
// 				selected_obj.flags = og_flags;
// 				selected_obj.vel = (get_world_mouse_pos() - mouse_last_pos) * 100;
// 				// selected.flags ~= u32(Physics_Object_Flag.Non_Kinematic);
// 				selected = {};
// 			}
// 			if any_selected {
// 				// FIXME: doesn't work with parent transforms
// 				setpos(selected_obj, get_world_mouse_pos());
// 				mouse_last_pos = get_world_mouse_pos();
// 			}

// 			if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) && !any_selected && dragging == false {
// 				dragging = true;
// 				drag_og = camera.pos + get_mouse_pos() / camera.zoom;
// 				follow_player = false;
// 			}
// 			if rl.IsMouseButtonReleased(rl.MouseButton.RIGHT) {
// 				dragging = false;
// 			}
// 			if dragging {
// 				camera.pos = drag_og - (get_mouse_pos() / camera.zoom);
// 			}

// 			mouse_move := rl.GetMouseWheelMove();
// 			if mouse_move != 0 {
// 				camera.zoom += mouse_move * 0.1;
// 			}

// 			if rl.IsKeyPressed(rl.KeyboardKey.B) do debug_toggle()
// 		}

// } // when DEBUG
		
		rl.EndDrawing();
	}

	rl.CloseWindow();
}
