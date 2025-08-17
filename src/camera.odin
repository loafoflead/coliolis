package main;
import rl "thirdparty/raylib";

/*
	pos: the top left of the camera's viewport
	scale: the size of the viewport, a width and height from 
		the top left
	basically its a Rectangle
*/
Camera2D :: struct {
	pos: Vec2,
	scale: Vec2,
	zoom: f32,
}

initialise_camera :: proc() {
	camera.scale = {f32(window_width), f32(window_height)};
	camera.zoom = 1;
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
	return (pos - (camera.pos - camera.scale / camera.zoom / 2)) * camera.zoom;
}

get_world_screen_centre :: proc() -> Vec2 {
	return camera.pos
}

get_world_mouse_pos :: proc() -> Vec2 {
	return ((camera.pos - camera.scale / camera.zoom / 2) + get_mouse_pos() / camera.zoom);
}

get_b2d_world_mouse_pos :: proc() -> Vec2 {
	return rl_to_b2d_pos(get_world_mouse_pos())
}