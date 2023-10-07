const std = @import("std");
const testing = std.testing;

pub const HeaderContentType = enum {
    TextPlain,
    JSON,

    pub fn toString(self: HeaderContentType) []const u8 {
        return switch (self) {
            .TextPlain => "text/plain",
            .JSON => "application/json",
        };
    }
};

test "HeaderContentType" {
    try testing.expect(std.mem.eql(u8, HeaderContentType.TextPlain.toString(), "text/plain"));
    try testing.expect(std.mem.eql(u8, HeaderContentType.JSON.toString(), "application/json"));
}