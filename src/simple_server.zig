const std = @import("std");
const http = std.http;
const log = std.log.scoped(.server);
const testing = std.testing;

pub const HeaderContentType = enum {
    Any,
    ImageSvg,
    ImageSvgXml,
    TextPlain,
    TextHtml,
    TextCss,
    JavaScript,
    JSON,

    pub fn toString(self: HeaderContentType) []const u8 {
        return switch (self) {
            .Any => "*/*",
            .ImageSvg => "image/svg",
            .ImageSvgXml => "image/svg+xml",
            .TextPlain => "text/plain",
            .TextHtml => "text/html",
            .TextCss => "text/css",
            .JavaScript => "text/javascript",
            .JSON => "application/json",
        };
    }
};

pub const SimpleServer = struct {
    server: http.Server = undefined,
    base_dir: []const u8 = "pages/",

    pub fn init(self: *SimpleServer, allocator: std.mem.Allocator, server_address: []const u8, server_port: u16) !void {
        self.server = http.Server.init(allocator, .{ .reuse_address = true });

        log.info("Server is running at {s}:{d}", .{ server_address, server_port });
        const address = std.net.Address.parseIp(server_address, server_port) catch unreachable;
        try self.server.listen(address);
    }

    pub fn runServer(self: *SimpleServer, allocator: std.mem.Allocator) !void {
        outer: while (true) {
            var response = try self.server.accept(.{
                .allocator = allocator,
            });
            defer response.deinit();

            while (response.reset() != .closing) {
                response.wait() catch |err| switch (err) {
                    error.HttpHeadersInvalid => continue :outer,
                    error.EndOfStream => continue,
                    else => return err,
                };

                try handleRequest(self, &response, allocator);
            }
        }
    }

    pub fn handleRequest(self: *SimpleServer, response: *http.Server.Response, allocator: std.mem.Allocator) anyerror!void {
        var timer = try std.time.Timer.start();
        log.info("{s} {s} {s}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });

        const body = try response.reader().readAllAlloc(allocator, 16777216);
        defer allocator.free(body);

        if (response.request.headers.contains("connection")) {
            try response.headers.append("connection", "close");
        }

        if (std.mem.startsWith(u8, response.request.target, "api")) {
            //Do API stuff
        } else {
            if (std.mem.eql(u8, response.request.target, "/")) {
                response.status = .ok;
                const root_file = "index.html";
                const root_path = try allocator.alloc(u8, self.base_dir.len + root_file.len);
                std.mem.copy(u8, root_path[0..], self.base_dir);
                std.mem.copy(u8, root_path[self.base_dir.len..], root_file);

                const file = try std.fs.cwd().readFileAlloc(allocator, root_path, 16777216);
                try response.headers.append("content-type", HeaderContentType.TextHtml.toString());
                try sendResponse(response, file);
            } else {
                const resource_path = response.request.target[1..];
                //const base_dir = "pages/";
                const key = try allocator.alloc(u8, self.base_dir.len + resource_path.len);
                std.mem.copy(u8, key[0..], self.base_dir);
                std.mem.copy(u8, key[self.base_dir.len..], resource_path);

                var resource_Exists: bool = true;
                std.fs.cwd().access(key, .{}) catch |err| {
                    log.info("{}", .{err});
                    if (err == std.os.AccessError.FileNotFound) {
                        resource_Exists = false;
                    }
                };

                if (resource_Exists == true) {
                    const file = try std.fs.cwd().readFileAlloc(allocator, key, 16777216);

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
        } else if (std.mem.endsWith(u8, resource, ".js")) {
            try response.headers.append("content-type", HeaderContentType.JavaScript.toString());
        } else if (std.mem.endsWith(u8, resource, ".svg")) {
            try response.headers.append("content-type", HeaderContentType.ImageSvgXml.toString());
        }
    }

    fn sendResponse(response: *http.Server.Response, data: []const u8) anyerror!void {
        response.transfer_encoding = .{ .content_length = data.len };
        try response.do();
        try response.writeAll(data);
        try response.finish();
    }
};

test "HeaderContentType" {
    try testing.expect(std.mem.eql(u8, HeaderContentType.TextPlain.toString(), "text/plain"));
    try testing.expect(std.mem.eql(u8, HeaderContentType.TextHtml.toString(), "text/html"));
    try testing.expect(std.mem.eql(u8, HeaderContentType.TextCss.toString(), "text/css"));
    try testing.expect(std.mem.eql(u8, HeaderContentType.JSON.toString(), "application/json"));
}
