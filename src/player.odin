package main;

PLAYER_HORIZ_ACCEL :: 10_000.0; // pixels per second
PLAYER_JUMP_STR :: 100.0; // idk

PLAYER_WIDTH :: 32;
PLAYER_HEIGHT :: 32;

PLAYER_WEIGHT_KG :: 5;

PLAYER_STEP_UP_HEIGHT :: 20;

Player :: struct {
	obj: Physics_Object_Id,
	texture: Texture_Id,
}

player_feet :: proc(player: ^Player) -> Vec2 {
	obj := phys_obj(player.obj);
	return obj.pos + Vec2 {0, PLAYER_HEIGHT / 2 - 2};
}

player_new :: proc(texture: Texture_Id) -> Player {
	player: Player;
	player.obj = add_phys_object_aabb(
		pos = get_screen_centre(), 
		mass = kg(PLAYER_WEIGHT_KG), 
		scale = Vec2 { PLAYER_WIDTH, PLAYER_HEIGHT },
		flags = {.Drag_Exception},
		collide_with = {.Default, .L0},
	);
	player.texture = texture;
	return player;
}

draw_player :: proc(player: ^Player) {
	obj:=phys_obj(player.obj);
	// r := phys_obj_to_rect(obj).zw;
	draw_phys_obj(player.obj);
	draw_rectangle_transform(obj, phys_obj_to_rect(obj), texture_id=player.texture);
	// draw_texture(player.texture, obj.pos, pixel_scale=phys_obj_to_rect(obj).zw);	
	// draw_rectangle(obj.pos - r/2, r);	
}
