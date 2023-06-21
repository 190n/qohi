const std = @import("std");
const Pixel = @This();

r: u8,
g: u8,
b: u8,
a: u8 = 0,

pub const PixelDifference = struct {
    r: i9,
    g: i9,
    b: i9,
    a: i9,
};

pub fn subtract(self: Pixel, rhs: Pixel) PixelDifference {
    return .{
        .r = @as(i9, self.r) - @as(i9, rhs.r),
        .g = @as(i9, self.g) - @as(i9, rhs.g),
        .b = @as(i9, self.b) - @as(i9, rhs.b),
        .a = @as(i9, self.a) - @as(i9, rhs.a),
    };
}

test "Pixel.subtract" {
    const a = Pixel{ .r = 40, .g = 30, .b = 20, .a = 10 };
    const b = Pixel{ .r = 4, .g = 16, .b = 64, .a = 255 };
    try std.testing.expectEqual(PixelDifference{ .r = 36, .g = 14, .b = -44, .a = -245 }, a.subtract(b));
}
