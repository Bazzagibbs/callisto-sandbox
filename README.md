# Callisto Sandbox

A sandbox project for the development of the [Callisto Engine](https://github.com/bazzagibbs/callisto).

## Build from source

1. Install the [Odin SDK](https://odin-lang.org/docs/install/)
2. Install a [Vulkan SDK](https://vulkan.lunarg.com/)
3. Clone this repository:
```sh
git clone --recursive https://github.com/Bazzas-Personal-Stuff/callisto-sandbox.git
```
- If you have already cloned without `--recursive`, the required submodules can be updated with: 
```sh
git submodule update --init --recursive
```
4. From the root directory, run the following command:
```sh
odin run . -debug -out:"./out/callisto-sandbox.exe" -o:"none"
```
- Alternatively on Windows, run the `run.bat` file, which executes the same command.
