package main;

import "core:math/linalg";
import "core:math";

// when ODIN_DEBUG { can't do dis..
	import "core:fmt";
// }

Mat3x3 :: linalg.Matrix3f32;
Mat2x2 :: linalg.Matrix2f32;
Vec3 :: linalg.Vector3f32;

Transform :: struct {
	using pos: Vec2,
	rot: f32,
	// TODO: this pointer is invalidated if the parent is updated... :(
	parent: ^Transform,
}

// // stole from: https://math.stackexchange.com/questions/525082/reflection-across-a-line
// matrix_reflect :: proc(mat: Mat2x2, line: Vec2) -> Mat2x2 {
// 	// y = mx
// 	m := line.y / line.x;
// 	factor := 1 / (1 + m*m);
// 	mat := Mat2x2 {
// 		1 - m*m, 2*m,
// 		2*m, m*m - 1,
// 	};
// 	return factor * mat;
// }

transform_reparent :: proc(new_parent: ^Transform, transform: ^Transform) -> Transform {
	mat := linalg.matrix3_inverse(transform_to_matrix(new_parent));
	res := mat * transform_to_matrix(transform);

	return transform_from_matrix(res);
}

transform_forward :: proc(transform: ^Transform) -> Vec2 {
	return Vec2 {
		math.cos(transform.rot),
		math.sin(transform.rot),
	}
}

transform_right :: proc(transform: ^Transform) -> Vec2 {
	fwd := transform_forward(transform);
	right_mat := linalg.matrix2_rotate_f32(linalg.π/2);
	return (right_mat * fwd).xy;
}

transform_point :: proc(transform: ^Transform, point: Vec2) -> Vec2 {
	mat := transform_to_matrix(transform);
	res := mat * Vec3 { point.x, point.y, 1 };
	return res.xy;
}

transform_to_matrix :: proc(transform: ^Transform) -> Mat3x3 {
	rot_mat := linalg.matrix2_rotate_f32(transform.rot);
	return Mat3x3 {
		rot_mat[0, 0], rot_mat[0, 1], transform.x,
		rot_mat[1, 0], rot_mat[1, 1], transform.y,
		0, 0, 1
	};
}

transform_from_matrix :: proc(mat: Mat3x3) -> Transform {
	rotation := math.atan2(mat[1, 0], mat[0, 0]);
	position := mat[2].xy;

	return Transform {
		pos = position,
		rot = rotation,
	}
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