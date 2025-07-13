package main;

PLAYER_HORIZ_ACCEL :: 5000.0; // pixels per second
PLAYER_JUMP_STR :: 1000.0; // idk

Player :: struct {
	obj: ^Physics_Object,
	obj_id: int,
}