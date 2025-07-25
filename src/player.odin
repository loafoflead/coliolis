package main;

PLAYER_HORIZ_ACCEL :: 5000.0; // pixels per second
PLAYER_JUMP_STR :: 1000.0; // idk

Player :: struct {
	obj: Physics_Object_Id,
	texture: Texture_Id,
}

draw_player :: proc(player: ^Player) {
	obj:=phys_obj(player.obj);
	draw_texture(player.texture, obj.pos, pixel_scale=phys_obj_to_rect(obj).zw);	
}
