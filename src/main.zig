const std = @import("std");
const http = std.http;
const log = std.log.scoped(.server);
const simple_server = @import("simple_server.zig").SimpleServer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var server = simple_server{.base_dir = "frontend/dist/"};
    try server.init(allocator, "127.0.0.1", 8000);
    defer server.server.deinit();

    server.runServer(allocator) catch |err| {
        log.err("server error: {}\n", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    };
}
