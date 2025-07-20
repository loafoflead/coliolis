package main;

World_Transform :: struct {
	pos: Vec2,
	rot: f32,
	parent: ^World_Transform,
	children: [dynamic]^World_Transform,
}

Local_Transform :: struct {
	pos: Vec2,
	rot: f32,
}

transform_to_local :: proc(transform: ^World_Transform) -> Local_Transform {
	if transform.parent == nil {
		return Local_Transform { 
			pos = transform.pos,
			rot = transform.rot,
		};
	}
	else {
		return Local_Transform { 
			// TODO: use transform_to_local(transform.parent) ?
			pos = transform.pos - transform.parent.pos,
			rot = transform.rot - transform.parent.rot,
		};
	}
}