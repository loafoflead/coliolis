package main;

import rlgl "thirdparty/raylib/rlgl";

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

draw_rectangle_transform :: proc(
		transform: ^Transform, 
		rect: Rect, 
		colour: Colour = Colour(255),
		texture_id: Texture_Id = -1,
		uv: [4]Vec2 = UV_FULL_IMAGE,
) {
	vertices := rect_to_points(rect);
	for &vert in vertices {
		vert = transform_point(transform, vert);
		vert = world_pos_to_screen_pos(camera, vert);
	}

	if texture_id != -1 {
		rlgl.SetTexture(resources.textures[texture_id].id);
	}
	else do rlgl.SetTexture(rlgl.GetTextureIdDefault());

    rlgl.Begin(rlgl.QUADS);
        rlgl.Color4ub(colour.r, colour.g ,colour.b ,colour.a);
        rlgl.Normal3f(0, 0, 1); // TODO: find out what this does

        for i in 0..<len(vertices) {
        	rlgl.TexCoord2f(uv[i].x, uv[i].y);
        	rlgl.Vertex2f(vertices[i].x, vertices[i].y);
        }
    rlgl.End();
}