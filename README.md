# Project description: 

A simple platformer made with [Raylib](https://www.raylib.com) (<3) to test out the [Odin language](https://odin-lang.org/) (it's cool).

# How to build

## Note: as of now the game has only been tested on Linux (specifically OpenSUSE) 

So if it runs on any other platforms you can attribute that to Raylib and Odin magic.

You will need the [Odin compiler](https://odin-lang.org/docs/install/) in your PATH (or Path if you're on Windows), ideally you would also have [Make](https://www.gnu.org/software/make/), but I just use it for convenience.

The game uses Odin's vendored Raylib bindings, which are in the 'thirdparty/raylib' folder, when I get the time I may make it an actual Git thirdparty dependency, for now it makes things easier to build.

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

## Mouse

- LEFT			: pick up a physics object under the cursor (TODO: make this the top one...) that can be dragged around the screen. If you chuck it (release while moving fast) velocity is added to the object so you can throw it.
- RIGHT			: pan the camera
- MIDDLE		: spawn an object displaying the world position of the cursor

## Gameplay

You can move around as the player, jumping and going left/right, as well as travel through portals. Panning the camera unlocks it from following the player, re-centre on the player by pressing *LEFT CONTROL*.
Pick up and move the portals using *LEFT CLICK* on the mouse, rotate them with the arrow keys and select them by pressing *LEFT ALT* to toggle which portal you have selected.

# Credits:

- Tileset (assets/level_tileset.png), created by [aimen23b](https://www.fiverr.com/aimen23b), distributed by (i guess owned by?) [foozle](www.foozle.io): https://foozlecc.itch.io/sci-fi-lab-tileset-decor-traps
- Tilemap generation software ([Tiled](http://www.mapeditor.org/)), the edition used: http://www.mapeditor.org/2025/01/28/tiled-1-11-2-released.html


# TODO:

- [] fix player collision sometimes freezing against flat surfaces
- [] add diagonal colliders (non AABB)
- [] change player movement speed, jump str, and gravity to better suit movement through portals
- [] fix just_teleported_to variable, make it a delay instead of a lock? or a percent of collision instead of complete non-intersection
- [] notion of 'Rendered' object, so that portal can render half of a thing through itself