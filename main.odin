package main;

import rl "raylib";
import "core:math/linalg";
import "core:math/linalg/hlsl";
import "core:math";
import "core:fmt";

window_width : i32 = 600;
window_height : i32 = 400;

get_screen_centre :: proc() -> Vec2 {
	return Vec2 { cast(f32) rl.GetScreenWidth() / 2.0, cast(f32) rl.GetScreenHeight() / 2.0 };
}

Vec2 :: [2]f32;
Rect :: [4]f32;

Player :: struct {
	obj: ^Physics_Object,
}

EARTH_GRAVITY :: 9.8;
// terminal velocity = sqrt((gravity * mass) / (drag coeff))
ARBITRARY_DRAG_COEFFICIENT :: 0.01;

Physics_Object :: struct {
	pos, vel, acc: Vec2,
	mass: f32,
	flags: u32,
	hitbox: Hitbox,
}

phys_obj_to_rect :: proc(obj: ^Physics_Object) -> Rect {
	return Rect {
		obj.pos.x, obj.pos.y, obj.hitbox.x, obj.hitbox.y,
	};
}

phys_obj_has_flag :: proc(obj: ^Physics_Object, flag: Physics_Object_Flag) -> bool {
	return obj.flags & u32(flag) != 0;
}

calculate_terminal_velocity :: proc(gravity, mass, drag: f32) -> f32 {
	return math.sqrt((gravity * mass) / drag);
}

kg :: proc(num: f32) -> f32 {
	return num * 1000.0;
}

Physics_Object_Flag :: enum u32 {
	Non_Kinematic 			= 1 << 0,
	No_Dampen_Velocity 		= 1 << 1,
	No_Collisions 			= 1 << 2,
	No_Gravity				= 1 << 3,
}

Hitbox :: [2]f32;

draw_hitbox_at :: proc(pos: Vec2, box: ^Hitbox) {
	hue := hlsl.fmod_float(linalg.length(box^), 360.0); // holy shit this is cool
	colour := rl.ColorFromHSV(hue, 1.0, 1.0);
	draw_rectangle(pos - (box^ / 2.0), cast(Vec2) box^);
}

update_physics_object :: proc(obj: ^Physics_Object, world: ^Physics_World, dt: f32) {
	if phys_obj_has_flag(obj, Physics_Object_Flag.Non_Kinematic) {
		return;
	}
	resistance: f32 = 0.0;
	if !phys_obj_has_flag(obj, Physics_Object_Flag.No_Dampen_Velocity) {
		resistance = ARBITRARY_DRAG_COEFFICIENT;
	}
	next_pos := obj.pos + obj.vel * dt;
	next_vel := (obj.vel + obj.acc * dt) - obj.vel * resistance;

	if !phys_obj_has_flag(obj, Physics_Object_Flag.No_Gravity) {
		obj.acc = {0, EARTH_GRAVITY} * obj.mass;
	}

	if phys_obj_has_flag(obj, Physics_Object_Flag.No_Collisions) {
		obj.pos = next_pos;
		obj.vel = next_vel;
		return;
	}

	for &other_obj in world.objects {
		r1 := phys_obj_to_rect(obj);
		r2 := phys_obj_to_rect(&other_obj);
		if rl.CheckCollisionRecs(transmute(rl.Rectangle) r1, transmute(rl.Rectangle) r2) {
			unimplemented("Collision solving"); 
		}
	}
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
	flags: u32  = 0
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
	for &obj in phys_world.objects {
		update_physics_object(&obj, &phys_world, dt);
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

draw_texture :: proc(texture_id: int, pos: Vec2) {
	if texture_id >= len(resources.textures) {
		fmt.println("Tried to draw nonexistent texture");
		return;
	}
	screen_pos := world_pos_to_screen_pos(camera, pos);
	rl.DrawTexture(resources.textures[texture_id], i32(screen_pos.x), i32(screen_pos.y), rl.WHITE);
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

Resources :: struct #no_copy {
	textures: [dynamic]rl.Texture2D,
}

initialise_resources :: proc() {
	resources.textures = make([dynamic]rl.Texture2D, 10);
}

free_resources :: proc() {
	delete(resources.textures)
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

// -------------- GLOBALS --------------
camera 		: Camera2D;
resources 	: Resources;
phys_world  : Physics_World;
// --------------   END   --------------

main :: proc() {
	rl.InitWindow(window_width, window_height, "yeah");
	
	initialise_camera();

	initialise_resources();
	defer free_resources();

	initialise_phys_world();
	defer free_phys_world();

	five_w, ok := load_texture("5W.png");
	if !ok do return;

	player: Player;
	player.obj = add_phys_object(pos = get_screen_centre(), mass = kg(1.0), scale = Vec2 { 100.0, 100.0 });
	fmt.println(calculate_terminal_velocity(EARTH_GRAVITY, player.obj.mass, ARBITRARY_DRAG_COEFFICIENT));
	player.obj.flags |= u32(Physics_Object_Flag.No_Collisions);

	add_phys_object(
		mass = 0.0, 
		scale = Vec2 {500.0, 100.0}, 
		pos = get_screen_centre() + Vec2 { 0, 500},
		flags = u32(Physics_Object_Flag.No_Collisions),
	);

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime();
		rl.BeginDrawing();
		rl.ClearBackground(rl.GetColor(0x181818));

		draw_texture(five_w, {0., 0.});
		for &obj in phys_world.objects {
			draw_hitbox_at(obj.pos, &obj.hitbox);
		}
		// camera.pos += Vec2 {10.0, 10.0} * dt;
		update_phys_world(dt);
		
		rl.EndDrawing();
	}

	rl.CloseWindow();
}