const std = @import("std");

// extern to make sure layout is as expected
pub const Pixel = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 0,
    pub fn subtract(self: Pixel, rhs: Pixel) PixelDifference {
        return .{
            .r = @as(i9, self.r) - @as(i9, rhs.r),
            .g = @as(i9, self.g) - @as(i9, rhs.g),
            .b = @as(i9, self.b) - @as(i9, rhs.b),
            .a = @as(i9, self.a) - @as(i9, rhs.a),
        };
    }

    pub fn hash(self: Pixel) u8 {
        return @truncate((3 *% self.r) +% (5 *% self.g) +% (7 *% self.b) +% (11 *% self.a));
    }
};

pub const PixelDifference = struct {
    r: i9,
    g: i9,
    b: i9,
    a: i9,

    pub fn isZero(self: PixelDifference) bool {
        return self.r == 0 and self.g == 0 and self.b == 0 and self.a == 0;
    }
};

test "Pixel.subtract" {
    const a = Pixel{ .r = 40, .g = 30, .b = 20, .a = 10 };
    const b = Pixel{ .r = 4, .g = 16, .b = 64, .a = 255 };
    try std.testing.expectEqual(PixelDifference{ .r = 36, .g = 14, .b = -44, .a = -245 }, a.subtract(b));
}

test "Pixel.hash" {
    const a = Pixel{ .r = 40, .g = 30, .b = 20, .a = 10 };
    const b = Pixel{ .r = 4, .g = 16, .b = 64, .a = 255 };
    const c = Pixel{ .r = 255, .g = 255, .b = 255, .a = 255 };
    try std.testing.expectEqual(@as(u8, 8), a.hash());
    try std.testing.expectEqual(@as(u8, 17), b.hash());
    try std.testing.expectEqual(@as(u8, 230), c.hash());
}
