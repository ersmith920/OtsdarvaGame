# Native swarm core (C++)

`swarm_core` is a small GDExtension with two classes. The compiled libraries live in
`res://bin/` and load automatically. You only need this folder if the C++ changes.

- `SwarmCore`: the movement, crowd grid, terrain cache, drawing buffers and hit queries of
  the enemy swarm (driven by `Scripts/swarm.gd`).
- `GoldCore`: every gold coin on the map: flight, bounces, swirl collection, merging and
  drawing buffers (driven by `Scripts/coins.gd`). Without the library, coins fall back to
  the `GoldPickup` node coin, which behaves the same. Change both if you change one.

`Scripts/swarm_core_gd.gd` is a line-for-line GDScript copy with the same functions. The
game uses it automatically when the native library isn't loaded (it's much slower).
If you change behavior in one, change the other to match.

## Rebuilding (Windows, Visual Studio + CMake)

1. Get godot-cpp next to this folder (branch 4.5 works with Godot 4.5 and newer):
   `git clone -b 4.5 https://github.com/godotengine/godot-cpp native/godot-cpp`
2. Configure and build:
   ```
   cmake -S native/swarm_core -B native/build -DGODOTCPP_TARGET=template_release
   cmake --build native/build --config Release
   ```
3. Copy `libswarm_core.windows.template_release.x86_64.dll` from the build folder into `bin/`
   (close Godot first: it locks the DLL while open).

The first build compiles godot-cpp and takes a while; later builds are quick.
