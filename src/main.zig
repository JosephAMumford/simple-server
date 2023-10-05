const std = @import("std");
const http = std.http;
const log = std.log.scoped(.server);

const server_address = "127.0.0.1";
const server_port = 8000;

fn runServer(server: *http.Server, allocator: std.mem.Allocator) !void {
    outer: while (true) {
        var response = try server.accept(.{
            .allocator = allocator,
        });
        defer response.deinit();

        while (response.reset() != .closing) {
            response.wait() catch |err| switch (err) {
                error.HttpHeadersInvalid => continue :outer,
                error.EndOfStream => continue,
                else => return err,
            };

            try handleRequest(&response, allocator);
        }
    }
}

fn handleRequest(response: *http.Server.Response, allocator: std.mem.Allocator) !void {
    log.info("{s} {s} {s}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });

    const body = try response.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(body);

    if (response.request.headers.contains("connection")) {
        try response.headers.append("connection", "close");
    }

    var response_message: []const u8 = undefined;

    if (std.mem.eql(u8, response.request.target, "/route1")) {
        response_message = routeOne(response);
    } else if (std.mem.eql(u8, response.request.target, "/route2")) {
        response_message = routeTwo();
    } else {
        response_message = "Not found";
        response.status = .ok;
    }

    std.log.info("{s}", .{response_message});

    if (response.status != .not_found) {
        try response.headers.append("content-type", "text/plain");

        try response.do();
        if (response.request.method != .HEAD) {
            response.transfer_encoding = .{ .content_length = response_message.len };
            try response.writeAll(response_message);
            try response.finish();
        }
    } else {
        try response.do();
    }
}

fn routeOne(response: *http.Server.Response) []const u8 {
    response.status = .created;
    return "Database results";
}

fn routeTwo() []const u8 {
    return "User logged in";
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var server = http.Server.init(allocator, .{ .reuse_address = true });
    defer server.deinit();

    log.info("Server is running at {s}:{d}", .{ server_address, server_port });
    const address = std.net.Address.parseIp(server_address, server_port) catch unreachable;
    try server.listen(address);

    runServer(&server, allocator) catch |err| {
        log.err("server error: {}\n", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        std.os.exit(1);
    };
}
