package main

import "core:container/queue"
import "core:log"

/*
	Messages are 'targeted' events, that are sent directly to a gameobject,
	events are like channels
*/

Game_Event_Type :: enum {
	Logic,
}

Game_Event_Set :: bit_set[Game_Event_Type]

Game_Event :: struct {
	sender: Game_Object_Id,
	name: string,

	payload: union{Logic_Event},
}

Logic_Event :: struct {
	activated: bool,
}

Collision :: struct {
	other: Game_Object_Id,
	self_obj, other_obj: ^Physics_Object,
}

Game_Object_Message_Payload :: union {
}

Game_Object_Message :: struct {
	gobj: Game_Object_Id,
	payload: Game_Object_Message_Payload,
}

queue_inform_game_object :: proc(obj: Game_Object_Id, payload: Game_Object_Message_Payload) {
	assert(obj != GAME_OBJECT_INVALID && int(obj) < len(game_state.objects) )

	queue.push_front(&game_state.messages, Game_Object_Message { gobj = obj, payload = payload })
}

inform_game_object :: proc(obj: Game_Object_Id, payload: Game_Object_Message_Payload) {
	assert(obj != GAME_OBJECT_INVALID && int(obj) < len(game_state.objects) )

	// gobj is so funny to me idk why
	gobj := game_obj(obj)

	switch data in payload {
	}
}

channel_from_string :: proc(s: string) -> (Game_Event_Type, bool) {
	switch s {
	case "Logic":
		return .Logic, true
	case "None":
		return {}, false
	case:
		log.errorf("Unknown channel '%s'", s)
		return {}, false
	}
}

events_subscribe :: proc(id: Game_Object_Id, event_tys: Game_Event_Set = {}) {
	game_state.event_subscribers[id] = event_tys
}

send_game_event :: proc(event: Game_Event) {
	assert(game_state.initialised)

	switch _ in event.payload {
	case Logic_Event:
		queue.push_front(&game_state.events[.Logic], event)
	case:
		log.error(event)
		unimplemented()
	}
}