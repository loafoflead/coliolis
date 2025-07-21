package main;

import "core:math/linalg";
import "core:math";

Transform :: struct {
	pos: Vec2,
	rot: f32,
	parent: ^Transform,
	children: [dynamic]^Transform,
}

Global_Transform :: struct {
	pos: Vec2,
	rot: f32,
}

world_pos_to_local :: proc(transform: ^Transform, pos: Vec2) -> Vec2 {
	if transform.parent == nil {
		return pos;
	}
	else {
		mag := linalg.length(pos);
		smth := Vec2 { math.cos(transform.parent.rot + transform.rot), math.sin(transform.parent.rot + transform.rot) };
		npos := transform.parent.pos - mag*smth;
		return npos;
	}
}

transform_to_world :: proc(transform: ^Transform) -> Global_Transform {
	if transform.parent == nil {
		return Global_Transform { 
			pos = transform.pos,
			rot = transform.rot,
		};
	}
	else {
		mag := linalg.length(transform.pos);
		smth := Vec2 { math.cos(transform.parent.rot - transform.rot), math.sin(transform.parent.rot - transform.rot) };
		pos := transform.parent.pos + mag*smth;
		return Global_Transform { 
			// TODO: use transform_to_local(transform.parent) ?
			pos = pos,
			rot = transform.rot + transform.parent.rot,
		};
	}
}