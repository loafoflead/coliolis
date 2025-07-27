package main;

import rl "thirdparty/raylib";
import "core:math";
import "core:fmt";
import "core:mem";

import "core:math/ease";

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

PORTAL_EXIT_SPEED_BOOST :: 10;

Portal_State :: enum {
	Connected,
	Alive,
}

Portal :: struct {
	obj: Physics_Object_Id,
	state: bit_set[Portal_State],
	occupant: Maybe(Physics_Object_Id),
	occupant_layers: bit_set[Collision_Layer],
	occupant_last_side: f32, // dot(occupant_to_portal_surface, portal_surface)
	occupant_last_new_pos: Vec2, // TODO: explain (to get vel)
	was_just_teleported_to: bool,
}

Portal_Handler :: struct {
	portals: [2]Portal,
	edge_colliders: [2]Physics_Object_Id,
}

initialise_portal_handler :: proc() {
	if !phys_world.initialised do os.exit(-1);

	portal_handler.portals.x.obj = add_phys_object_aabb(
		scale = Vec2 { 20.0, 80.0 },
		flags = {.Non_Kinematic},
		collision_layers = {.Trigger},
		collide_with = COLLISION_LAYERS_ALL,
	);
	portal_handler.portals.y.obj = add_phys_object_aabb(
		scale = Vec2 { 20.0, 80.0 },
		flags = {.Non_Kinematic},
		collision_layers = {.Trigger},
		collide_with = COLLISION_LAYERS_ALL,
	);
	portal_handler.edge_colliders = {
		add_phys_object_aabb(
			pos = {0, -50},
			scale = Vec2 { 20.0, 20.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
		),
		add_phys_object_aabb(
			pos = {0, 50},
			scale = Vec2 { 20.0, 20.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
		),
	}
}
free_portal_handler :: proc() {}

draw_portals :: proc(selected_portal: int) {
	for &portal, i in portal_handler.portals {
		value: f32;
		hue := f32(1);
		sat := f32(1);
		switch i {
			case 0: value = 60;  // poiple
			case 1: value = 115; // Grüne
			case: 	value = 0;	 // röt
		}
		_, occupied := portal.occupant.?;
		if occupied {
			// positive = behind
			if portal.occupant_last_side > 0 do value = 0;
			else do value = 115;
		}
		if portal.was_just_teleported_to do sat = 0;
		// TODO: messed up HSV pls fix it l8r
		colour := transmute(Colour) rl.ColorFromHSV(value, sat, hue);
		draw_phys_obj(portal.obj, colour);
		// draw_rectangle(pos=obj.pos, scale=obj.hitbox, rot=obj.rot, col=colour);
	}
	for edge in portal_handler.edge_colliders {
		colour := transmute(Colour) rl.ColorFromHSV(1.0, 1.0, 134);

		draw_phys_obj(edge, colour);
	}
}

import "core:math/linalg";

// TODO: make player a global?
update_portals :: proc(collider: Physics_Object_Id) {
	for &portal, i in portal_handler.portals {
		occupant_id, occupied := portal.occupant.?;

		collided := check_phys_objects_collide(portal.obj, collider);
		if collided && !occupied && !portal.was_just_teleported_to {
			portal.occupant = collider;
			obj := phys_obj(collider);
			portal.occupant_layers = obj.collide_with_layers;
			obj.collide_with_layers = {.L0};
		}
		else {
			if occupied && !collided {
				obj := phys_obj(occupant_id);
				obj.collide_with_layers = portal.occupant_layers;
				portal.occupant = nil;
				portal.was_just_teleported_to = false;
			}
		}

		if !occupied || portal.was_just_teleported_to do continue;

		obj := phys_obj(occupant_id);
		portal_obj := phys_obj(portal.obj);

		// phys_obj(portal_handler.edge_colliders[0]).parent = portal_obj;
		// phys_obj(portal_handler.edge_colliders[1]).parent = portal_obj;

		to_occupant_centre := obj.pos - phys_obj_centre(portal_obj);
		side := linalg.dot(to_occupant_centre, -transform_forward(portal_obj));

		other_portal := &portal_handler.portals[1 if i == 0 else 0];
		other_portal_obj := phys_obj(other_portal.obj);

		using linalg;
		oportal_mat := other_portal_obj.mat;
		portal_mat := portal_obj.mat;
		obj_mat := obj.mat;

		mirror := Mat4x4 {
			-1, 0,  0, 0,
			0, 1, 	0, 0,
			0, 0, 	1, 0,
			0, 0, 0, 1,
		}

		obj_local := matrix4_inverse(portal_mat) * obj_mat;
		relative_to_other_portal := mirror * obj_local;

		fmat := oportal_mat * relative_to_other_portal;

		ntr := transform_from_matrix(fmat);
		// ntr.pos += other_portal_obj.pos;

		if side >= 0 && portal.occupant_last_side < 0 {
			other_portal.was_just_teleported_to = true;
			other_portal.occupant = occupant_id;
			other_portal.occupant_layers = portal.occupant_layers;

			obj.vel = normalize(ntr.pos - portal.occupant_last_new_pos) * (length(obj.vel) + PORTAL_EXIT_SPEED_BOOST);
			// obj.acc = normalize(ntr.pos - portal.occupant_last_new_pos) * (length(obj.acc) + PORTAL_EXIT_SPEED_BOOST);
			obj.local = ntr;

			obj.collide_with_layers = portal.occupant_layers;
			portal.occupant = nil;
		}
		portal.occupant_last_new_pos = ntr.pos;
		portal.occupant_last_side = side;
	}
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

	player: Player;
	player.obj = add_phys_object_aabb(
		pos = get_screen_centre(), 
		mass = kg(1.0), 
		scale = Vec2 { 30.0, 30.0 },
		flags = {.Drag_Exception}, 
	);
	player.texture = five_w;

	portal_handler.portals.x.state += {.Alive};
	portal_handler.portals.y.state += {.Alive};

	in_air: bool;
	jump_timer := get_temp_timer(0.2);
	jumping: bool;
	coyote_timer := get_temp_timer(0.25);

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
		if is_timer_done(debug_timer) {
			// debug printing here
		}

		dt := rl.GetFrameTime();

		rl.BeginDrawing();
		rl.ClearBackground(rl.GetColor(BACKGROUND_COLOUR));

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
		draw_phys_obj(test_obj);
		// ------------   END   ------------

		// ------------ UPDATING ------------
		update_phys_world(dt);
		update_portals(player.obj);
		update_timers(dt);
		// ------------    END   ------------

		// vvvvvv <- random testing stuff ahead

		phys_obj(a).rot += 1 * dt;

		rotate: f32;
		portal_obj := phys_obj(portal_handler.portals[selected_portal].obj);
		if rl.IsKeyPressed(rl.KeyboardKey.LEFT) {
			rotate = 1;
		}
		else if rl.IsKeyPressed(rl.KeyboardKey.RIGHT) {
			rotate = -1;
		}
		else do rotate = 0;

		if rl.IsKeyPressed(rl.KeyboardKey.F) {
			portal_obj.local = transform_flip(portal_obj);
		}
		portal_obj.rot += rotate * math.PI/2;
		if rl.IsKeyPressed(rl.KeyboardKey.LEFT_ALT) do selected_portal = 1 - selected_portal;

		if rl.IsKeyPressed(rl.KeyboardKey.LEFT_CONTROL) do follow_player = true;

		if !dragging && selected == -1 && follow_player do camera.pos = player_obj.pos - get_screen_centre();

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


		if move != 0.0 {
			player_obj.acc.x = move * PLAYER_HORIZ_ACCEL;
		}
		else {
			player_obj.acc.x = 0.0;
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