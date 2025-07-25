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

# Credits:

- Tileset (assets/level_tileset.png), created by [aimen23b](https://www.fiverr.com/aimen23b), distributed by (i guess owned by?) [foozle](www.foozle.io): https://foozlecc.itch.io/sci-fi-lab-tileset-decor-traps
- Tilemap generation software ([Tiled](http://www.mapeditor.org/)), the edition used: http://www.mapeditor.org/2025/01/28/tiled-1-11-2-released.html