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
	None,
	Logic,
}

Game_Event_Category_Set :: bit_set[Game_Event_Category]
Game_Event_Payload :: union{Activation_Event, Cube_Die, Level_Event, Simple_Event}

Game_Event :: struct {
	sender: Game_Object_Id,
	name: string,
	categories: Game_Event_Category_Set,

	payload: Game_Event_Payload,
}

Simple_Event :: struct{}

Activation_Event :: struct {
	activated: bool,
}

Cube_Die :: struct {
	event_name: string,
}

Level_Event :: enum {
	End,
	Load,
}

Game_Object_Message_Payload :: union {
}

// DM for gameobjects (deprecated/unused(?))
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
		return .None, true
	case:
		log.errorf("Unknown channel '%s'", s)
		return .None, true
	}
}

events_subscribe :: proc(id: Game_Object_Id) {
	append(&game_state.event_subscribers, id)
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

send_game_event_done :: proc(event: Game_Event) {
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
			categories = event.categories,
			payload = event.payload,
			sender = event.sender,
		}
		queue.push_front(&game_state.events, event)
	}
}

send_new_game_event :: proc(channel: string, payload: Game_Event_Payload) {
	send_game_event_done(Game_Event {
		name = channel,
		payload = payload,
	})
}

send_game_event :: proc{send_new_game_event, send_game_event_done}

game_events_this_frame :: proc() -> []Game_Event {
	return game_state.events.data[:]
}