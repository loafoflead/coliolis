# Project description: 

A simple platformer made with [Raylib](https://www.raylib.com) (<3) to test out the [Odin language](https://odin-lang.org/) (it's cool).

# How to build

## Note: as of now the game has only been tested on Linux (specifically OpenSUSE) 

So if it runs on any other platforms you can attribute that to Raylib and Odin magic.

You will need the [Odin compiler](https://odin-lang.org/docs/install/) in your PATH (or Path if you're on Windows), ideally you would also have [Make](https://www.gnu.org/software/make/), but I just use it for convenience.

## Prerequisites:

- You need clang to compile Odin on Linux, on Debian that's: ```apt install clang```, but I imagine it's much the same for different package maangers.
- Box2d vendor needs to be built, need curl, cmake, *(TODO better explain)*
- The game uses Odin's vendored Raylib bindings, which are expected to be in the ```src/thirdparty/raylib``` folder. In order to build the project you need to copy the vendored raylib from your installation of Odin to this folder, like so (on Linux, on Windows you may prefer to use the file manager):

- Note: The version of these bindings are from the Odin installation ```dev-2025-07-nightly``` 
  + Raylib Version: 4.2.0
  + Box2D Version: v3.0

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

# Use the Odin compiler to build the project:

The project's build system is inspired by Tsoding's [NoBuild](https://github.com/tsoding/nobuild/blob/master/nobuild.h) project. 

Run: 
```terminal
$ odin build build.odin -file
$ ls
src/
assets/
build.odin
build
<...>
```

Then to build the project, simply run ./build. Thanks to innovative ```GO_REBUILD_URSELF(tm)``` technology, changes to the build script will cause it to automagically rebuild itself (so will moving it between directories but oh well).

To just check, use ```./build -mode:check```, and to run ```./build -mode:run```. To add ggdb debug symbols, use ```-debug```, to check for unused variables use ```-vet```, and to rebuild assets use ```assets```.

The above list probably isn't exhaustive as you're reading this, so to find a 'list' of all available subcommands check the build.odin script, specifically searching for the ```Cmd_Options``` structure and it's sub-structures(is that a thing???).

That's the slight disadvantage of this style of build system, which is that it doesn't self-document, but the flexibility advantage and (if done correctly...) significant lesser complexity (as in, easier to simply express things that are complicated in build system scripting languages (like variables for some stupid reason (yes i hate specifically Cmake))) which i think just about outweighs the cons of a less 'readable' build script.

### notes:

The custom attribute ```interface``` doesn't do anything, it's just there for me to see at a glance (I hate writing IStruct_Name or I_Struct_Name).

```
$ ./build
odin run src -out:bin/main
INFO: Initializing raylib 5.5
INFO: Platform backend: DESKTOP (GLFW)
INFO: Supported raylib modules:
INFO:     > rcore:..... loaded (mandatory)
<...>
```

And if everything works (and the code compiles...) it should run.

## Current flags available:

- 'debug': compiles with ggdb debug symbols
- 'and_run': compiles and runs
- 'vet': add extra strict vet rules

# Useful code: 

1. The section of the project that parses 'Tiled' tilemaps might be useful to others, it's in the ```tiled``` folder. The code is dead simple though, just about worth copy pasting the ```parse_tileset``` function
1. ```physics.odin``` demonstrates usage of Box2D (messy...)
1. ```build.odin``` shows how to create a very basic build system in a single file 
1. ```portals.odin``` shows odin lang's excellent swizzling and linear algebra support
1. ```main``` procedure illustrates how to very simply use Raylib in Odin

# How to play

The game itself is currently unfinished, any controls or gameplay listed below could be out of date or no longer exist.

## Gameplay keybinds

- A, D (WASD)	: movement from left to right for the player
- SPACE			: jump for the player (hold = longer jump)
- LCONTROL 		: hold down for mouse clicks to fire portals

## Debug/testing keybinds

- B 			: enable continuous debug printing
- L 			: Unlock a portal
- J 			: enable debug mode (move the camera)

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

(TODO, if you want info you'll need to look thru the levels for now to see what properties spawn different game objects)

# Credits:

- Tileset (assets/level_tileset.png), created by [aimen23b](https://www.fiverr.com/aimen23b), distributed by (i guess owned by?) [foozle](www.foozle.io): https://foozlecc.itch.io/sci-fi-lab-tileset-decor-traps
- Tilemap generation software ([Tiled](http://www.mapeditor.org/)), the edition used: http://www.mapeditor.org/2025/01/28/tiled-1-11-2-released.html

# TODO:

- [ ] change player movement speed, jump str, and gravity to better suit movement through portals
- [ ] notion of 'Rendered' object, so that portal can render half of a thing through itself
