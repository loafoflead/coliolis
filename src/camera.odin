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

get_world_mouse_pos :: proc() -> Vec2 {
	return camera.pos + get_mouse_pos();
}

// if drawn_portion is zero, the whole picture is used
draw_texture :: proc(
	texture_id: Texture_Id, 
	pos: Vec2, 
	drawn_portion: Rect = MARKER_RECT,
	scale: Vec2 = MARKER_VEC2,
	pixel_scale: Vec2 = MARKER_VEC2,
) {
	if int(texture_id) >= len(resources.textures) {
		unimplemented("Tried to draw nonexistent texture");
	}
	screen_pos := world_pos_to_screen_pos(camera, pos);
	rotation := f32(0.0);
	tex := resources.textures[int(texture_id)];

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