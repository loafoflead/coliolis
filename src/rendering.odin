package main;

import rlgl "thirdparty/raylib/rlgl";
import rl "thirdparty/raylib";

import b2d "thirdparty/box2d"

UV_FULL_IMAGE : [4]Vec2 : {
	{0,0},
	{0, 1},
	{1, 1},
	{1, 0},
};

rect_to_points :: proc(rect: Rect) -> [4]Vec2 {
	// OpenGL order: topleft -> bottomleft -> bottomright -> topright
	// how did i learn this you ask? well, allow me to introduce you to my friend:
	// !!!!!!!! ** * ù*ù* * Trial and bloody error!! !!ù ! *ùm* * * * é??
	topleft := Vec2(0);
	return [4]Vec2 {
		topleft,
		topleft + Vec2{0, rect.w},
		topleft + rect.zw,
		topleft + Vec2{rect.z, 0},
	}
}

draw_polygon_convex :: proc(
	transform: b2d.Transform,
	vertices: []Vec2,
	colour: Colour = Colour(255),
) {
	vertices := vertices
	for &vert in vertices {
		vert = b2d.TransformPoint(transform, vert)
		vert = b2d_to_rl_pos(vert)
		vert = world_pos_to_screen_pos(camera, vert)
		// TODO: rot
	}

	rlgl.Begin(rlgl.QUADS);
        rlgl.Color4ub(colour.r, colour.g ,colour.b ,colour.a);
        rlgl.Normal3f(0, 0, 1); // TODO: find out what this does

    	for vert, i in vertices {
        	// rlgl.TexCoord2f(uv[i].x, uv[i].y);
        	rlgl.Vertex2f(vert.x, vert.y);
        }
    rlgl.End();
}

draw_circle :: proc(pos: Vec2, radius: f32) {
	pos := world_pos_to_screen_pos(camera, pos)
	rl.DrawCircle(cast(i32)pos.x, cast(i32)pos.y, radius * camera.zoom, rl.DARKBLUE);
}

draw_rectangle_transform :: proc(
		transform: ^Transform, 
		rect: Rect, 
		colour: Colour = Colour(255),
		texture_id := TEXTURE_INVALID,
		uv: [4]Vec2 = UV_FULL_IMAGE,
) {
	vertices := rect_to_points(rect);
	for &vert in vertices {
		vert -= rect.zw / 2;
		vert = transform_point(transform, vert);
		vert = world_pos_to_screen_pos(camera, vert);
	}

	if texture_id != TEXTURE_INVALID {
		rlgl.SetTexture(resources.textures[texture_id].id);
	}
	else do rlgl.SetTexture(rlgl.GetTextureIdDefault());

	cam_scaled_rect := rect;
	cam_scaled_rect.xy *= camera.zoom; // TODO: make this a proc in the camera file

	// transform without rotation on the y and x axis
	aligned_transform := transform_new(transform.pos, transform.rot)

    rlgl.Begin(rlgl.QUADS);
        rlgl.Color4ub(colour.r, colour.g ,colour.b ,colour.a);
        rlgl.Normal3f(0, 0, 1); // TODO: find out what this does

        // if aligned_transform != transform^ {
	    //     #reverse for vert, i in vertices {
	    //     	rlgl.TexCoord2f(uv[i].x, uv[i].y);
	    //     	rlgl.Vertex2f(vert.x - cam_scaled_rect.x/2, vert.y - cam_scaled_rect.y/2);
	    //     }
        // } else {
        	for vert, i in vertices {
	        	rlgl.TexCoord2f(uv[i].x, uv[i].y);
	        	rlgl.Vertex2f(vert.x - cam_scaled_rect.x/2, vert.y - cam_scaled_rect.y/2);
	        }
        // }
    rlgl.End();
}


// if drawn_portion is zero, the whole picture is used
draw_texture :: proc(
	texture_id: Texture_Id, 
	pos: Vec2, 
	rotation: f32 = 0,
	drawn_portion: Rect = MARKER_RECT,
	scale: Vec2 = MARKER_VEC2,
	pixel_scale: Vec2 = MARKER_VEC2,
	tint := Colour(255),
) {
	if int(texture_id) >= len(resources.textures) {
		unimplemented("Tried to draw nonexistent texture");
	}
	screen_pos := world_pos_to_screen_pos(camera, pos);
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

	dest.zw *= camera.zoom; // TODO: make this a proc in the camera file
	
	rl.DrawTextureNPatch(
		tex, 
		n_patch_info, 
		transmute(rl.Rectangle) dest, // destination
		transmute(rl.Vector2) -screen_pos + dest.zw / 2, 
		rotation,
		cast(rl.Color)tint,
	);
}

draw_line :: proc(start, end: Vec2, colour: Colour = Colour{255, 0,0,255}) {
	screen_start := world_pos_to_screen_pos(camera, start);
	screen_end := world_pos_to_screen_pos(camera, end);

	rl.DrawLineV(transmute(rl.Vector2) screen_start, transmute(rl.Vector2) screen_end, transmute(rl.Color) colour);
}