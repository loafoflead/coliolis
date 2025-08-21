package main;

import rl "thirdparty/raylib";
import rlgl "thirdparty/raylib/rlgl"
import b2d "thirdparty/box2d"
import "core:math";
import "core:fmt";
import "core:mem";

import "core:math/linalg";
import "core:math/ease"

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
particle_handler: Particle_Handler

window_width : i32 = 600;
window_height : i32 = 400;

debug_print: bool = false;
// --------------   END   --------------

BACKGROUND_COLOUR :: 0x181818;
TILEMAP :: 
	"portals_intro.tmj"
	// "cube_intro.tmj" 
	// "cube_portal.tmj"

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

	initialise_timers()
	defer free_timers()

	initialise_particle_handler()
	defer free_particle_handler()

	initialise_game_state()
	defer free_game_state()

	initialise_portal_handler();
	defer free_portal_handler();

	five_w, ok := load_texture("5W.png")
	if !ok do os.exit(1)

	dir_tex, ok = load_texture("nesw_sprite.png")
	if !ok do os.exit(1)

	

	game_load_level_from_tilemap(TILEMAP)

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

	debug_mode: bool = false

	follow_player := true

	collision: Maybe(Ray_Collision)

	test_particle := Particle_Def {
		draw_info = Particle_Draw_Info {
			shape = .Square,
			texture = dir_tex,
			scale = Vec2(10),
			colour = Colour(255),
			alpha_easing = .Bounce_In,
		},
		lifetime_secs = 2,
		movement = Particle_Physics {
			perm_acc = Vec2(0),
			initial_conds = Particle_Init_Random {
				vert_spread = 100,
				horiz_spread = 100,
				vel_dir_max = 360,
				vel_mag_max = 20,
				ang_vel_min = -100,
				ang_vel_max = 100,
			}
		}
	}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		if rl.IsWindowResized() {
			window_width = rl.GetScreenWidth()
			window_height = rl.GetScreenHeight()
			camera.scale = Vec2{cast(f32)window_width, cast(f32)window_height}
		}

		update_phys_world()
		update_game_state(dt)
		// update_portals();
		update_portals(physics.bodies[1])
		update_timers(dt)
		update_particles(dt)



		rl.BeginDrawing()
		rl.ClearBackground(rl.GetColor(BACKGROUND_COLOUR))

		// ntrans := transform_new(0, 0)
		// draw_rectangle_transform(
		// 	&ntrans,
		// 	Rect {0, 0, 100, 30},
		// 	texture_id = portal_handler.textures[0],
		// )

		// particle_spawn({50, 50}, 35, test_particle)

		// draw_phys_world()
		render_game_objects(camera)
		// draw_texture(dir_tex, pos=rl_to_b2d_pos(get_world_mouse_pos()), scale=0.1)
		draw_tilemap(state_level().tilemap, {0., 0.});
		draw_portals(selected_portal);
		render_particles()

		if follow_player {
			camera.pos = player_pos()
		}


		click: int
		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) do click = 1
		else if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) do click = 2

		if click != 0 && click <= game_obj(game_state.player, Player).portals_unlocked {
			player_pos := player_pos()
			col, hit := cast_ray_in_world(
				player_pos,
				linalg.normalize(get_world_mouse_pos() - player_pos) * PORTAL_RANGE,
				exclude = {get_player().obj},
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
		// draw_line(player_pos, player_pos + linalg.normalize(get_world_mouse_pos() - player_pos) * 50)

		if rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL) {
			player_pos := player_pos()
			
			selected_id, any_selected := selected.?
			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && dragging == false {
				obj_id, ok := point_collides_in_world(get_world_mouse_pos());
				if ok {
					dist := linalg.length(phys_obj_pos(obj_id) - player_pos)
					if obj_id != get_player().obj && dist < PLAYER_REACH {
						og_ty = b2d.Body_GetType(obj_id)
						if og_ty == b2d.BodyType.dynamicBody {
							selected = obj_id;

							def := b2d.DefaultMouseJointDef()
							if !b2d.Body_IsValid(mouse_ptr_body) {
								mouse_ptr_body_def := b2d.DefaultBodyDef()
								mouse_ptr_body = b2d.CreateBody(physics.world, mouse_ptr_body_def)
							}
							def.bodyIdA = mouse_ptr_body
							def.bodyIdB = obj_id
							def.maxForce = 100_000
							def.hertz = 16
							def.target = b2d.Body_GetPosition(obj_id)
							def.collideConnected = false

							mouse_joint = b2d.CreateMouseJoint(physics.world, def)
						}
					}
				}
			}
			if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) && any_selected {
				if b2d.Joint_IsValid(mouse_joint) {
					b2d.DestroyJoint(mouse_joint)
					mouse_joint = b2d.nullJointId
				}

				selected = nil;
			}
			if any_selected {
				target := get_world_mouse_pos()
				dist := linalg.length(get_world_mouse_pos() - player_pos)
				if dist > PLAYER_REACH {
					target = player_pos + linalg.normalize(get_world_mouse_pos() - player_pos) * PLAYER_REACH
				}
				if b2d.Joint_IsValid(mouse_joint) {
					jdist := linalg.length(get_world_mouse_pos() - phys_obj_pos(selected_id))
					if jdist > SNAP_LIMIT && dist > PLAYER_REACH {
						if b2d.Joint_IsValid(mouse_joint) {
							b2d.DestroyJoint(mouse_joint)
							mouse_joint = b2d.nullJointId
						}

						selected = nil;
					}
					else {
						b2d.MouseJoint_SetTarget(
							mouse_joint,
							rl_to_b2d_pos(target),
						)
					}
				}
				dist_frac := dist / PLAYER_REACH
				if dist_frac == 0 do dist_frac = 0.01
				green := f32(105)
				red := f32(0)
				hue := green - (green * dist_frac)
				draw_line(
					player_pos,
					target, 
					cast(Colour)rl.ColorFromHSV(hue, 1, 1)
				)

				mouse_last_pos = get_world_mouse_pos();
			}
		}
		else {
			if b2d.Joint_IsValid(mouse_joint) {
				b2d.DestroyJoint(mouse_joint)
				mouse_joint = b2d.nullJointId
			}

			selected = nil;
		}

		rl.EndDrawing()

when DEBUG {
		if rl.IsKeyPressed(rl.KeyboardKey.J) do debug_mode = !debug_mode

		if debug_mode {
			selected_id, any_selected := selected.?
			// if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) && dragging == false {
			// 	obj_id, ok := point_collides_in_world(get_world_mouse_pos());
			// 	log.info(obj_id)
			// 	if ok {
			// 		og_ty = b2d.Body_GetType(obj_id)
			// 		if og_ty != b2d.BodyType.staticBody {
			// 			// b2d.Body_SetType(obj_id, b2d.BodyType.dynamicBody)
			// 			selected = obj_id;

			// 			def := b2d.DefaultMouseJointDef()
			// 			def.bodyIdA = mouse_ptr_body
			// 			def.bodyIdB = obj_id
			// 			def.maxForce = 10000000
			// 			def.target = b2d.Body_GetPosition(obj_id)
			// 			def.collideConnected = false

			// 			mouse_joint = b2d.CreateMouseJoint(physics.world, def)
			// 			selected_is_static = false
			// 		}
			// 		else {
			// 			selected_is_static = true
			// 			selected = obj_id
			// 		}
			// 	}
			// }
			// if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) && any_selected {
			// 	if b2d.Joint_IsValid(mouse_joint) {
			// 		log.info("goop")
			// 		b2d.DestroyJoint(mouse_joint)
			// 		mouse_joint = b2d.nullJointId
			// 	}
			// 	// if !selected_is_static {
			// 		// b2d.Body_SetLinearVelocity(selected_id, (get_world_mouse_pos() - mouse_last_pos) * 100)
			// 	// }

			// 	selected = nil;
			// }
			// if any_selected {
			// 	mpos := get_b2d_world_mouse_pos()
			// 	if selected_is_static {
			// 		b2d.Body_SetTransform(selected_id, mpos, {1, 0})
			// 	}
			// 	else if b2d.Joint_IsValid(mouse_joint) {
			// 		b2d.MouseJoint_SetTarget(
			// 			mouse_joint,
			// 			rl_to_b2d_pos(get_world_mouse_pos()),
			// 		)
			// 	}
			// 	// b2d.Body_SetTransform(mouse_ptr_body, get_world_mouse_pos(), b2d.Body_GetRotation(mouse_ptr_body))
			// 	mouse_last_pos = get_world_mouse_pos();
			// }

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

			// if rl.IsKeyPressed(rl.KeyboardKey.K) do b2d.Body_SetTransform(portal_handler.portals[0].obj, get_b2d_world_mouse_pos(), {1, 0})
			// if rl.IsKeyPressed(rl.KeyboardKey.L) do b2d.Body_SetTransform(portal_handler.portals[1].obj, get_b2d_world_mouse_pos(), {1, 0})
			if rl.IsKeyPressed(rl.KeyboardKey.T) do player_goto(get_world_mouse_pos())
			if rl.IsKeyPressed(rl.KeyboardKey.N) do send_game_event("lvl", Level_Event.End)

			if rl.IsKeyPressed(rl.KeyboardKey.B) do debug_toggle()
		}

} // when DEBUG
	}
}

// _ :: proc() {
	
// 		if click != 0 && click <= player.portals_unlocked {
// 			hit: bool
// 			collision, hit = cast_ray_in_world(
// 				player_obj.pos, 
// 				linalg.normalize(get_world_mouse_pos() - phys_obj_world_pos(player_obj)),
// 				layers = {.Portal_Surface}
// 			)
// 			if hit {
// 				prtl_obj := phys_obj(portal_handler.portals[click - 1].obj)
// 				og := Vec3{collision.point.x, collision.point.y, 0}
// 				pt := og + Vec3{collision.normal.x, collision.normal.y, 0}
// 				quat := linalg.quaternion_look_at(og, pt, Z_AXIS)

// 				// facing := linalg.yaw_from_quaternion(quat)
// 				x, y, z := linalg.euler_angles_xyz_from_quaternion(quat)
// 				facing := z + linalg.PI/2

// 				obstructed := cast_box_in_world(
// 					collision.point.xy + collision.normal.xy * (portal_dims().x/2 + 0.5), 
// 					portal_dims(), 
// 					Rad(facing),
// 					exclude = {player.obj},
// 					layers = {.Default},
// 				)
// 				if !obstructed {
// 					setrot(prtl_obj, Rad(facing))
// 					if collision.normal.x == 0 {
// 						if collision.normal.y < 0 {
// 							rotate(prtl_obj, Rad(linalg.PI))
// 						} else {
// 							prtl_obj.local = transform_flip(prtl_obj)
// 						}
// 					}
// 					else if collision.normal.x < 0 {
// 						rotate(prtl_obj, Rad(linalg.PI))
// 					}
// 					else {
// 						prtl_obj.local = transform_flip(prtl_obj)
// 					}

// 					portal_handler.portals[click - 1].state += {.Alive}

// 					// prtl_obj.local.mat =
// 					// 	linalg.matrix4_look_at_f32(og, og + pt * 10, Z_AXIS)
// 					// transform_reset_rotation_plane(prtl_obj)
// 					// transform_update(portal_obj)
// 					setpos(prtl_obj, collision.point.xy - collision.normal.xy * 8)
// 				}
// 			}
// 		}