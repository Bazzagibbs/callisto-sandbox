# Callisto Sandbox

A sandbox project for the development of the [Callisto Engine](https://github.com/bazzagibbs/callisto).

## Build from source

> [!Note]
> Slangc is included with the Vulkan SDK. If you already have the SDK installed, you may skip step 2.

1. Install the [Odin SDK](https://odin-lang.org/docs/install/)
2. Install the [Slang Compiler](https://github.com/shader-slang/slang/releases) and add it to your path.
3. Clone this repository:
```sh
git clone --recursive https://github.com/Bazzagibbs/callisto-sandbox.git
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
