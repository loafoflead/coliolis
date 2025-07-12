package main;

World_Transform :: struct {
	pos: Vec2,
	parent: ^World_Transform,
	children: [dynamic]^World_Transform,
}

Local_Transform :: struct {
	pos: Vec2,
}

transform_to_local :: proc(transform: ^World_Transform) -> Local_Transform {
	if transform.parent == nil {
		return Local_Transform { 
			pos = transform.pos 
		};
	}
	else {
		return Local_Transform { 
			pos = transform.pos - transform.parent.pos 
		};
	}
}