# Project description: 

A simple platformer made with [Raylib](https://www.raylib.com) (<3) to test out the [Odin language](https://odin-lang.org/) (it's cool).

# How to build

## Note: as of now the game has only been tested on Linux (specifically OpenSUSE) 

So if it runs on any other platforms you can attribute that to Raylib and Odin magic.

You will need the [Odin compiler](https://odin-lang.org/docs/install/) in your PATH (or Path if you're on Windows), ideally you would also have [Make](https://www.gnu.org/software/make/), but I just use it for convenience.

## Prerequisites:

- You need clang to compile Odin on Linux, on Debian that's: ```apt install clang```, but I imagine it's much the same for different package maangers.
- The game uses Odin's vendored Raylib bindings, which are expected to be in the ```src/thirdparty/raylib``` folder. In order to build the project you need to copy the vendored raylib from your installation of Odin to this folder, like so (on Linux, on Windows you may prefer to use the file manager):

```
$ pwd
/path/to/this/coliolis
$ mkdir src/thirdparty
$ cp -r $ODIN_ROOT/vendor/raylib ./src/thirdparty
$ ls 
<source files...> main.odin thirdparty
$ ls src/thirdparty
raylib
```

- Finally, create a file called ```bin``` in the root directory of the project, if you're using Make.

## With Make:

Navigate to the root folder ```coliolis/``` for me, and just run 'make'

```
$ pwd
/home/user/<whatever>/coliolis
$ ls
assets/
bin/
src/
makefile
README.md
$ make
odin run src -out:bin/main
INFO: Initializing raylib 5.5
INFO: Platform backend: DESKTOP (GLFW)
INFO: Supported raylib modules:
INFO:     > rcore:..... loaded (mandatory)
<...>
```

And if everything works (and the code compiles...) it should run.

## Without Make:

I just used make to output to the right folder, so without it you have to navigate to the ```src/``` folder and run the contents of the makefile:

```
$ pwd
/home/user/<whatever>/coliolis
$ odin run src -out:bin/main
INFO: Initializing raylib 5.5
INFO: Platform backend: DESKTOP (GLFW)
INFO: Supported raylib modules:
<...>
```

Good luck!

# Useful code: 

1. The section of the project that parses 'Tiled' tilemaps might be useful to others, it's in the ```tiled``` folder. The code is dead simple though, just about worth copy pasting the ```parse_tileset``` function.
1. ```update_phys_obj``` procedure showcases Odin's excellent swizzling, maths, fixed array programming stuff, and it's brilliant.
1. ```main``` procedure illustrates how to very simply use Raylib in Odin.

# How to play

The game itself is currently unfinished, any controls or gameplay listed below could be out of date or no longer exist.

## Gameplay keybinds

- A, D (WASD)	: movement from left to right for the player
- SPACE			: jump for the player (hold = longer jump)
- LCONTROL 		: focus camera on player position

## Debug/testing keybinds

- LALT 			: switch selected portal
- F 			: flip facing direction of selected portal
- LEFT, RIGHT 	: rotate selected portal by 90 degrees in either direction
- G, H 			: rotate player object in the left or right direction while held
- B 			: enable continuous debug printing

## Mouse

- LEFT			: pick up a physics object under the cursor (TODO: make this the top one...) that can be dragged around the screen. If you chuck it (release while moving fast) velocity is added to the object so you can throw it.
- RIGHT			: pan the camera
- MIDDLE		: spawn an object displaying the world position of the cursor

## Gameplay

You can move around as the player, jumping and going left/right, as well as travel through portals. Panning the camera unlocks it from following the player, re-centre on the player by pressing *LEFT CONTROL*.
Pick up and move the portals using *LEFT CLICK* on the mouse, rotate them with the arrow keys and select them by pressing *LEFT ALT* to toggle which portal you have selected.

## Level creation

Levels are made using the Tiled editor (credits below)

### Naming conventions

- Player spawn
```json 
{
	"name": "<whatever you want>",
	"tiled_class": "Point",
	"properties": {
		"type": "player_spawn"
	}
}
```

- Layer properties
 + 'generate' property (arguments: string)
  + 'static_collision'	: generate collision boxes for each tile on this layer
  + 'hurt'				: generate hurt boxes for each tile on this layer
 + 'no_render' property (arguments: none \[technically a string but nothing is expected\])
Will skip rendering this layer
- Object types
 + 'marker' type, indicates that this is a marker (spawnpoint, camera focus point, etc...)
  + 'type' property of the 'marker' type, indicates what this marker is, one of (may be out of date!):
   1. cam_focus_point: exclusive focus point for the camera in this level
   1. player_spawn: player respawn point
   1. level_exit: location of the level exit trigger

# Credits:

- Tileset (assets/level_tileset.png), created by [aimen23b](https://www.fiverr.com/aimen23b), distributed by (i guess owned by?) [foozle](www.foozle.io): https://foozlecc.itch.io/sci-fi-lab-tileset-decor-traps
- Tilemap generation software ([Tiled](http://www.mapeditor.org/)), the edition used: http://www.mapeditor.org/2025/01/28/tiled-1-11-2-released.html


# TODO:

- [X] fix player collision sometimes freezing against flat surfaces
- [ ] add diagonal colliders (non AABB)
- [X] change player movement speed, jump str, and gravity to better suit movement through portals
- [X] fix just_teleported_to variable, make it a delay instead of a lock? or a percent of collision instead of complete non-intersection
- [ ] notion of 'Rendered' object, so that portal can render half of a thing through itself
