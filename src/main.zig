const std = @import("std");
const http = std.http;
const log = std.log.scoped(.server);
const HeaderContentType = @import("utilities.zig").HeaderContentType;

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
    var timer = try std.time.Timer.start();

    log.info("{s} {s} {s}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });

    const body = try response.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(body);

    if (response.request.headers.contains("connection")) {
        try response.headers.append("connection", "close");
    }

    var response_message: []const u8 = undefined;

    if (std.mem.eql(u8, response.request.target, "/route1")) {
        response_message = routeOne(response);
        try response.headers.append("content-type", HeaderContentType.TextPlain.toString());

        try sendResponse(response, response_message);
    } else if (std.mem.eql(u8, response.request.target, "/route2")) {
        response_message = routeTwo(response);
        try response.headers.append("content-type", HeaderContentType.JSON.toString());

        try sendResponse(response, response_message);
    } else if (std.mem.eql(u8, response.request.target, "/route3")) {
        response_message = routeThree(response);
        try response.headers.append("content-type", HeaderContentType.TextHtml.toString());

        try sendResponse(response, response_message);
    } else if (std.mem.startsWith(u8, response.request.target, "/get")) {
        response_message = routeOne(response);
        try response.headers.append("content-type", HeaderContentType.TextPlain.toString());

        try sendResponse(response, response_message);
    } else {
        response.status = .not_found;
        try sendResponse(response, "Resource not found");
    }

    const time_end_ns = timer.read();
    const time_end_us: u64 = time_end_ns / 1000;
    const time_end_ms = @as(f64, @floatFromInt(time_end_us)) / 1000.0;
    std.log.info("{}ns : {}us : {}ms", .{ time_end_ns, time_end_us, time_end_ms });
}

fn sendResponse(response: *http.Server.Response, data: []const u8) anyerror!void {
    response.transfer_encoding = .{ .content_length = data.len };
    try response.do();
    try response.writeAll(data);
    try response.finish();
}

fn routeOne(response: *http.Server.Response) []const u8 {
    response.status = .created;
    return "Database results";
}

fn routeTwo(response: *http.Server.Response) []const u8 {
    response.status = .ok;
    return "{\"message\":\"User logged in\"}";
}

fn routeThree(response: *http.Server.Response) []const u8 {
    response.status = .ok;

    return "<!DOCTYPE html><html><body><h1>Route 3</h1><p>Test HTML Template</p></body></html>";
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
    };
}
