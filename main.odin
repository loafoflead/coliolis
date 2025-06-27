package main;

import rl "raylib";
import "core:math/linalg";
import "core:log";

window_width : i32 = 600;
window_height : i32 = 400;

get_screen_centre :: proc() -> Vec2 {
	return Vec2 { cast(f32) rl.GetScreenWidth() / 2.0, cast(f32) rl.GetScreenHeight() / 2.0 };
}

Vec2 :: [2]f32;
Rect :: [4]f32;

Player :: struct {
	pos, vel, acc: Vec2,
	using hitbox: Hitbox,
}

Transform :: struct {
	translation, scale: Vec2,
}

Hitbox :: [2]f32;

draw_hitbox_at :: proc(pos: Vec2, box: ^Hitbox) {
	value := linalg.length(box^); // holy shit this is cool
	colour := rl.ColorFromHSV(1.0, 1.0, value);
	draw_rectangle(pos - (box^ / 2.0), cast(Vec2) box^);
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
		log.warn("Tried to draw nonexistent texture");
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

Resources :: struct {
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
// --------------   END   --------------

main :: proc() {
	rl.InitWindow(window_width, window_height, "yeah");
	
	initialise_camera();

	initialise_resources();
	defer free_resources();

	five_w, ok := load_texture("5W.png");
	if !ok do return;

	player: Player;
	player.pos = get_screen_centre();
	player.hitbox = Hitbox {100.0, 100.0};

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime();
		rl.BeginDrawing();
		rl.ClearBackground(rl.GetColor(0x181818));

		draw_texture(five_w, {0., 0.});
		draw_hitbox_at(player.pos, &player);
		camera.pos += Vec2 {10.0, 10.0} * dt;
		
		rl.EndDrawing();
	}

	rl.CloseWindow();
}