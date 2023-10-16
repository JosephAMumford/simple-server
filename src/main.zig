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

fn handleRequest(response: *http.Server.Response, allocator: std.mem.Allocator) anyerror!void {
    var timer = try std.time.Timer.start();
    log.info("{s} {s} {s}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });

    const body = try response.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(body);

    if (response.request.headers.contains("connection")) {
        try response.headers.append("connection", "close");
    }

    if (std.mem.startsWith(u8, response.request.target, "api")) {
        //Do API stuff
    } else {
        if (std.mem.eql(u8, response.request.target, "/")) {
            response.status = .ok;

            const file = try std.fs.cwd().readFileAlloc(allocator, "pages/index.html", 8192);
            try response.headers.append("content-type", HeaderContentType.TextHtml.toString());
            try sendResponse(response, file);
        } else {
            const resource_path = response.request.target[1..];
            const base_dir = "pages/";
            const key = try allocator.alloc(u8, base_dir.len + resource_path.len);
            std.mem.copy(u8, key[0..], base_dir);
            std.mem.copy(u8, key[base_dir.len..], resource_path);

            var resource_Exists: bool = true;
            std.fs.cwd().access(key, .{}) catch |err| {
                log.info("{}", .{err});
                if (err == std.os.AccessError.FileNotFound) {
                    resource_Exists = false;
                }
            };

            if (resource_Exists == true) {
                const file = try std.fs.cwd().readFileAlloc(allocator, key, 8192);

                response.status = .ok;
                try setContentType(response, resource_path);
                try sendResponse(response, file);
            } else {
                try response.headers.append("content-type", HeaderContentType.TextPlain.toString());
                response.status = .not_found;
                try sendResponse(response, "Resource not found");
            }
        }
    }

    const time_end_ns = timer.read();
    const time_end_us: u64 = time_end_ns / 1000;
    const time_end_ms = @as(f64, @floatFromInt(time_end_us)) / 1000.0;

    log.info("Response time {}ns : {}us : {d:.2}ms", .{ time_end_ns, time_end_us, time_end_ms });
}

fn setContentType(response: *http.Server.Response, resource: []const u8) !void {
    if (std.mem.endsWith(u8, resource, ".html")) {
        try response.headers.append("content-type", HeaderContentType.TextHtml.toString());
    } else if (std.mem.endsWith(u8, resource, ".css")) {
        try response.headers.append("content-type", HeaderContentType.TextCss.toString());
    }
}

fn sendResponse(response: *http.Server.Response, data: []const u8) anyerror!void {
    response.transfer_encoding = .{ .content_length = data.len };
    try response.do();
    try response.writeAll(data);
    try response.finish();
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
