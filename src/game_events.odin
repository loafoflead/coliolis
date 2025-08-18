package main

import "core:container/queue"
import "core:log"
import "core:strings"
import "core:slice"

/*
	Messages are 'targeted' events, that are sent directly to a gameobject,
	events are like channels
*/

Game_Event_Category :: enum {
	Logic,
}

Game_Event_Set :: bit_set[Game_Event_Category]

Game_Event :: struct {
	sender: Game_Object_Id,
	name: string,

	payload: union{Logic_Event, Cube_Die},
}

Logic_Event :: struct {
	activated: bool,
}

Cube_Die :: struct {
	event_name: string,
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

channel_from_string :: proc(s: string) -> (Game_Event_Category, bool) {
	switch s {
	case "Logic":
		return .Logic, true
	case "Cube_Die":
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

event_matches :: proc(event_name: string, my_events: string) -> bool {
	events : []string

	if strings.contains_rune(my_events, ',') {
		// TODO: game state get arena :D (i love arenas <3)
		events = strings.split(my_events, ",", allocator = context.temp_allocator)
	}
	else {
		events = {my_events}
	}

	return slice.contains(events, event_name)
}

send_game_event :: proc(event: Game_Event) {
	assert(game_state.initialised)

	events : []string

	if strings.contains_rune(event.name, ',') {
		// TODO: game state get arena :D (i love arenas <3)
		events = strings.split(event.name, ",", allocator = context.temp_allocator)
	}
	else {
		events = {event.name}
	}

	for e_name in events {
		event := Game_Event {
			name = e_name,
			payload = event.payload,
			sender = event.sender,
		}
		switch _ in event.payload {
		case Logic_Event:
			queue.push_front(&game_state.events[.Logic], event)
		case Cube_Die:
			queue.push_front(&game_state.events[.Logic], event)
		case:
			log.error(event)
			unimplemented()
		}
	}
}