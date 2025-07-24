package main;

import "core:math/linalg";
import "core:math";

// when ODIN_DEBUG { can't do dis..
	import "core:fmt";
// }

Mat3x3 :: matrix[3, 3]f32;
Vec3 :: linalg.Vector3f32;

Transform :: struct {
	using pos: Vec2,
	rot: f32, // facing
	parent: ^Transform,
}

world_pos_to_local :: proc(transform: ^Transform, pos: Vec2) -> Vec2 {
	if transform.parent == nil {
		return pos;
	}
	else {
		unimplemented("todo world_pos_to_local");
	}
}

transform_point :: proc(transform: ^Transform, point: Vec2) -> Vec2 {
	mat := transform_to_matrix(transform);
	res := mat * Vec3 { point.x, point.y, 1 };
	return res.xy;
}

transform_rect :: proc(transform: ^Transform, rect: Rect) -> Rect {
	mat := transform_to_matrix(transform);
	top_left := Vec3 { rect.x, rect.y, 0};
	bottom_right := top_left + Vec3 { rect.z, rect.w, 0};
	top_left = mat * top_left;
	bottom_right = mat * bottom_right;
	return Rect {
		top_left.x, top_left.y, bottom_right.x, bottom_right.y,
	}
}

transform_to_matrix :: proc(transform: ^Transform) -> Mat3x3 {
	rot_mat := linalg.matrix2_rotate_f32(transform.rot);
	return Mat3x3 {
		rot_mat[0, 0], rot_mat[0, 1], transform.x,
		rot_mat[1, 0], rot_mat[1, 1], transform.y,
		0, 0, 1
	};
}

transform_to_world :: proc(transform: ^Transform) -> Transform {
	if transform.parent == nil {
		return Transform { 
			pos = transform.pos,
			rot = transform.rot,
		};
	}
	else {
		parent := transform_to_world(transform.parent);
		parent_mat := transform_to_matrix(&parent);
		mat := transform_to_matrix(transform);
		res := parent_mat * mat;

		// rot_mat := matrix2_rotate_f32(transform.parent.rot);
		// mag := linalg.length(transform.pos);
		// smth := Vec2 { math.cos(transform.parent.rot - transform.rot), math.sin(transform.parent.rot - transform.rot) };
		// pos := transform.parent.pos + mag*smth;
		return Transform { 
			pos = res[2].xy,
			rot = transform.rot + parent.rot,
		};
	}
}