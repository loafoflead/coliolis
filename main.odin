package main;

import rl "raylib";
import "core:math/linalg";
import "core:math/linalg/hlsl";
import "core:math";
import "core:fmt";

import "core:os";

import "core:strings";

import "tiled";

window_width : i32 = 600;
window_height : i32 = 400;

BACKGROUND_COLOUR :: 0xFF00FFFF;// 0x181818;

get_screen_centre :: proc() -> Vec2 {
	return Vec2 { cast(f32) rl.GetScreenWidth() / 2.0, cast(f32) rl.GetScreenHeight() / 2.0 };
}

get_mouse_pos :: proc() -> Vec2 {
	return Vec2 { cast(f32) rl.GetMouseX(), cast(f32) rl.GetMouseY() };
}

get_world_mouse_pos :: proc() -> Vec2 {
	return camera.pos + get_mouse_pos();
}

Vec2 :: [2]f32;
Rect :: [4]f32;

ZERO_VEC2 :: Vec2{0,0};
MARKER_VEC2 :: Vec2 { math.F32_MAX, math.F32_MAX };
MARKER_RECT :: Rect { math.F32_MAX, math.F32_MAX, math.F32_MAX, math.F32_MAX };

PLAYER_HORIZ_ACCEL :: 50_000_000_000_000.0;

Player :: struct {
	obj: ^Physics_Object,
}

EARTH_GRAVITY :: 9.8;
// terminal velocity = sqrt((gravity * mass) / (drag coeff))
ARBITRARY_DRAG_COEFFICIENT :: 0.01;

Transform :: struct {
	pos: Vec2,
	parent: ^Transform,
	children: [dynamic]^Transform,
}

Physics_Object :: struct {
	using transform: Transform,
	vel, acc: Vec2,
	mass: f32,
	flags: Physics_Object_Flagset,
	hitbox: Hitbox,
}

phys_obj_to_rect :: proc(obj: ^Physics_Object) -> Rect {
	return Rect {
		obj.pos.x, obj.pos.y, obj.hitbox.x, obj.hitbox.y,
	};
}

calculate_terminal_velocity :: proc(gravity, mass, drag: f32) -> f32 {
	return math.sqrt((gravity * mass) / drag);
}

kg :: proc(num: f32) -> f32 {
	return num * 1000.0;
}

Physics_Object_Flag :: enum u32 {
	Non_Kinematic 			= 1 << 0,
	No_Velocity_Dampening 	= 1 << 1,
	No_Collisions 			= 1 << 2,
	No_Gravity				= 1 << 3,
}

Physics_Object_Flagset :: bit_set[Physics_Object_Flag];

Hitbox :: [2]f32;

draw_hitbox_at :: proc(pos: Vec2, box: ^Hitbox) {
	hue := hlsl.fmod_float(linalg.length(box^), 360.0); // holy shit this is cool
	colour := rl.ColorFromHSV(hue, 1.0, 1.0);
	draw_rectangle(pos, cast(Vec2) box^);
}

update_physics_object :: proc(obj_id: int, world: ^Physics_World, dt: f32) {
	obj := &phys_world.objects[obj_id];
	if Physics_Object_Flag.Non_Kinematic in obj.flags {
		return;
	}
	resistance: f32 = 1.0;
	if Physics_Object_Flag.No_Velocity_Dampening not_in obj.flags {
		resistance = 1.0 - ARBITRARY_DRAG_COEFFICIENT;
	}
	
	// if linalg.length(obj.vel) < MINIMUM_VELOCITY_MAGNITUDE do obj.vel = Vec2{};

	next_pos := obj.pos + obj.vel * dt;

	next_vel := (obj.vel + obj.acc * dt) * resistance;

	if Physics_Object_Flag.No_Gravity not_in obj.flags {
		obj.acc = {0, EARTH_GRAVITY} * obj.mass;
	}

	if Physics_Object_Flag.No_Collisions not_in obj.flags {
		for &other_obj, i in world.objects {
			if 
				i == obj_id || Physics_Object_Flag.No_Collisions in other_obj.flags
			{ continue; }

			r1 := transmute(rl.Rectangle) Rect { next_pos.x, next_pos.y, obj.hitbox.x, obj.hitbox.y };
			r2 := transmute(rl.Rectangle) phys_obj_to_rect(&other_obj);
			if rl.CheckCollisionRecs(r1, r2) {
				collision_rect := rl.GetCollisionRec(r1, r2);
				// use obj.pos instead of next_pos so we know where we came from
				move_back := linalg.normalize((obj.pos + obj.hitbox / 2.0) - (other_obj.pos + other_obj.hitbox / 2.0));
				// choose the smallest of the two coordinates to move back by
				if collision_rect.width > collision_rect.height {
					sign := -1.0 if move_back.y < 0.0 else f32(1.0);
					move_back.y = collision_rect.height * sign;
					next_vel.y = -next_vel.y;

					move_back.x = 0.0;
				}
				else {
					sign := -1.0 if move_back.x < 0.0 else f32(1.0);
					move_back.x = collision_rect.width * sign;
					next_vel.x = -next_vel.x;

					move_back.y = 0.0;
				}
				next_pos += move_back;
			}
		}
	}

	delta := next_pos - obj.pos;
	obj.pos = next_pos;
	for &child in obj.transform.children {
		child.pos += delta;
	}
	obj.vel = next_vel;
}

Physics_World :: struct #no_copy {
	objects: [dynamic]Physics_Object,
	// timestep: f32,
}

initialise_phys_world :: proc() {
	phys_world.objects = make([dynamic]Physics_Object, 0, 10);
}

free_phys_world :: proc() {
	delete(phys_world.objects);
}

add_phys_object :: proc(
	mass:  f32,
	scale: Vec2, 
	pos:   Vec2 = Vec2{}, 
	vel:   Vec2 = Vec2{}, 
	acc:   Vec2 = Vec2{}, 
	flags: Physics_Object_Flagset = {}
) -> ^Physics_Object 
{
	obj := Physics_Object {
		pos = pos, 
		vel = vel, 
		acc = acc, 
		mass = mass, 
		flags = flags, 
		hitbox = cast(Hitbox) scale,
	};
	append(&phys_world.objects, obj);
	return &phys_world.objects[len(phys_world.objects)-1];
}

update_phys_world :: proc(dt: f32) {
	for _, i in phys_world.objects {
		update_physics_object(i, &phys_world, dt);
	}
}

draw_rectangle :: proc(pos, scale: Vec2) {
	screen_pos := world_pos_to_screen_pos(camera, pos);
	rl.DrawRectangle(
		cast(i32) screen_pos.x,
		cast(i32) screen_pos.y,
		cast(i32) scale.x,
		cast(i32) scale.y, rl.RED
	);
}

// if drawn_portion is zero, the whole picture is used
draw_texture :: proc(
	texture_id: int, 
	pos: Vec2, 
	drawn_portion: Rect = MARKER_RECT,
	scale: Vec2 = MARKER_VEC2,
	pixel_scale: Vec2 = MARKER_VEC2,
) {
	if texture_id >= len(resources.textures) {
		fmt.println("Tried to draw nonexistent texture");
		return;
	}
	screen_pos := world_pos_to_screen_pos(camera, pos);
	rotation := f32(0.0);
	tex := resources.textures[texture_id];

	n_patch_info: rl.NPatchInfo;
	dest: Rect;

	// n_patch_info.source = transmute(rl.Rectangle) Rect {
	// 	0, 0,
	// 	200, 200
	// 	// cast(f32)tex.width  - 350, 
	// 	// cast(f32)tex.height - 350,
	// };
	// dest = Rect{0, 0, cast(f32)tex.width - 350, cast(f32)tex.height - 350};

	// TODO: bounds check this
	if drawn_portion == MARKER_RECT {
		n_patch_info.source = 
			transmute(rl.Rectangle) Rect {0, 0, cast(f32)tex.width, cast(f32)tex.height};
	}
	else {
		n_patch_info.source = //transmute(rl.Rectangle) Rect{0, 0, 32, 32};
			transmute(rl.Rectangle) drawn_portion;
	}

	if scale != MARKER_VEC2 && pixel_scale != MARKER_VEC2 do return;

	if scale == MARKER_VEC2 && pixel_scale == MARKER_VEC2 {
		dest = Rect {
			0, 0,
			cast(f32)tex.width, cast(f32)tex.height
		};
	}
	else if scale != MARKER_VEC2 {
		dest = Rect {
			0, 0,
			scale.x * cast(f32)tex.width, scale.y * cast(f32)tex.height
		};
	}
	else if pixel_scale != MARKER_VEC2 {
		dest = Rect {
			0, 0,
			pixel_scale.x, pixel_scale.y
		};
	}
	else {
		unreachable();
	}
	
	rl.DrawTextureNPatch(
		tex, 
		n_patch_info, 
		transmute(rl.Rectangle) dest, // destination
		transmute(rl.Vector2) -screen_pos, 
		rotation,
		rl.WHITE
	);
}

/*
	pos: the top left of the camera's viewport
	scale: the size of the viewport, a width and height from 
		the top left
	basically its a Rectangle
*/
Camera2D :: struct {
	pos: Vec2,
	scale: Vec2,
}

initialise_camera :: proc() {
	camera.scale = {f32(window_width), f32(window_height)};
}

camera_rect :: proc(camera: Camera2D) -> rl.Rectangle {
	return rl.Rectangle { 
		camera.pos.x, 
		camera.pos.y, 
		camera.scale.x,
		camera.scale.y
	};
}

is_rect_visible_to_camera :: proc(camera: Camera2D, rect: Rect) -> bool {
	r1 := camera_rect(camera);
	r2 := transmute(rl.Rectangle) rect; // they are in fact, the same thing
	return rl.CheckCollisionRecs(r1, r2);
}

world_pos_to_screen_pos :: proc(camera: Camera2D, pos: Vec2) -> Vec2 {
	return pos - camera.pos;
}

Tilemap :: struct {
	using tilemap: tiled.Tilemap,
	texture_id: int,
}

Resources :: struct #no_copy {
	textures: [dynamic]rl.Texture2D,
	tilemaps: [dynamic]Tilemap,
}

initialise_resources :: proc() {
	resources.textures = make([dynamic]rl.Texture2D, 10);
	resources.tilemaps = make([dynamic]Tilemap, 10);
}

free_resources :: proc() {
	delete(resources.textures);
	// TODO: check if the xml library requires unloading
	delete(resources.tilemaps);
}

load_texture :: proc(path: cstring) -> (int, bool) {
	tex := rl.LoadTexture(path);
	success := rl.IsTextureValid(tex);
	index := len(resources.textures);
	if success {
		append(&resources.textures, tex);
	}
	return index, success;
}

load_tilemap :: proc(path: string) -> (index: int, err: bool = true) {
	tilemap := tiled.parse_tilemap(path) or_return;
	
	builder := strings.builder_make(context.temp_allocator);
	defer strings.builder_destroy(&builder);

	strings.write_string(&builder, tilemap.tileset.source);

	texture_id := load_texture(strings.to_cstring(&builder)) or_return;

	index = len(resources.tilemaps);
	append(&resources.tilemaps, Tilemap { tilemap = tilemap, texture_id = texture_id });

	return;
}

generate_static_physics_for_tilemap :: proc(tilemap: int, layer: int) {
	layer := resources.tilemaps[tilemap].layers[layer];
	for y in 0..<layer.height {
		for x in 0..<layer.width {
			tile := layer.data[y * layer.width + x];
			// NOTE: zero seems to mean nothing, so all offsets have one added to them
			if tile == 0 do continue;

		}
	}
}

draw_tilemap :: proc(index: int, pos: Vec2) {
	// TODO: blit the entire tilemap into a texture and draw that instead of doing this every frame
	src_idx := resources.tilemaps[index].texture_id;
	tileset := resources.tilemaps[index].tileset;
	DRAWN_LAYER :: 0;
	layer := resources.tilemaps[index].layers[DRAWN_LAYER];
	for y in 0..<layer.height {
		for x in 0..<layer.width {
			tile := layer.data[y * layer.width + x];
			// NOTE: zero seems to mean nothing, so all offsets have one added to them
			if tile == 0 do continue;
			tile -= 1;
			// TODO: figure out what these magic values mean
			if tile >= 1610612788 do continue; //tile == 1610612806 || tile == 1610612807 || tile == 1610612797 || tile == 1610612788 do continue;

			// the index of the tile in the source image
			tile_x := tile % tileset.columns;
			tile_y := (tile - tile_x) / (tileset.columns);

			tile_pos := pos + Vec2 {cast(f32)x, cast(f32)y} * Vec2 {cast(f32)tileset.tilewidth, cast(f32)tileset.tileheight};
			drawn_portion := Rect { 
				cast(f32)(tile_x * tileset.tilewidth),
				cast(f32)(tile_y * tileset.tileheight),
				cast(f32) tileset.tilewidth,
				cast(f32) tileset.tileheight,
			};
			draw_texture(src_idx, tile_pos, drawn_portion = drawn_portion, pixel_scale = Vec2{cast(f32)tileset.tilewidth, cast(f32)tileset.tileheight});
		}
	}
}

// -------------- GLOBALS --------------
camera 		: Camera2D;
resources 	: Resources;
phys_world  : Physics_World;
// --------------   END   --------------

main :: proc() {	
	initialise_camera();

	initialise_resources();
	defer free_resources();

	initialise_phys_world();
	defer free_phys_world();

	rl.InitWindow(window_width, window_height, "yeah");

	five_w, ok := load_texture("5W.png");
	if !ok do os.exit(1);
	
	test_map, tmap_ok := load_tilemap("second_map.tmx");
	if !tmap_ok do os.exit(1);


	player: Player;
	player.obj = add_phys_object(pos = get_screen_centre(), mass = kg(1.0), scale = Vec2 { 30.0, 30.0 });
	fmt.println(calculate_terminal_velocity(EARTH_GRAVITY, player.obj.mass, ARBITRARY_DRAG_COEFFICIENT));

	add_phys_object(
		mass = 10.0,
		scale = Vec2 {500.0, 50.0},
		pos = get_screen_centre() + Vec2 { 0, 150 },
		flags = {.Non_Kinematic},
	);

	selected: ^Physics_Object;
	og_flags: Physics_Object_Flagset;

	dragging: bool;
	drag_og: Vec2;

	pointer : Vec2;

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime();
		rl.BeginDrawing();
		rl.ClearBackground(rl.GetColor(BACKGROUND_COLOUR));

		draw_tilemap(test_map, {0., 0.});
		for &obj in phys_world.objects {
			draw_hitbox_at(obj.pos, &obj.hitbox);
		}
		// camera.pos += Vec2 {10.0, 10.0} * dt;
		update_phys_world(dt);

		move: f32 = 0.0;
		if rl.IsKeyDown(rl.KeyboardKey.D) {
			move +=  1;
		}
		if rl.IsKeyDown(rl.KeyboardKey.A) {
			move += -1;
		}

		if move != 0.0 {
			// acc = 1/2 * force / mass * t²
			player.obj.acc.x = (move * PLAYER_HORIZ_ACCEL) * dt*dt / player.obj.mass;
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