const std = @import("std");
const Encoder = @This();

const Pixel = @import("./pixel.zig").Pixel;
const PixelDifference = @import("./pixel.zig").PixelDifference;
const Qoi = @import("./qoi.zig");

last_pixel: Pixel = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
recent_pixels: [64]Pixel = .{.{ .r = 0, .g = 0, .b = 0, .a = 0 }} ** 64,
run_length: u6 = 0,
histogram: Qoi.Histogram = Qoi.Histogram.init(),
total_qoi_size: usize = 0,

pub fn init(allocator: std.mem.Allocator) Encoder {
    _ = allocator;
    return .{};
}

pub fn deinit(self: *Encoder) void {
    self.* = undefined;
}

fn emit(self: *Encoder, chunk: Qoi.Chunk) !void {
    // std.debug.print("{any}\n", .{chunk});
    var buf: [5]Qoi.Symbol = undefined;
    const syms = chunk.toSymbols(&buf);

    for (syms) |s| {
        self.histogram.increment(s);
    }

    self.total_qoi_size += switch (chunk) {
        .rgb => 4,
        .rgba => 5,
        .index => 1,
        .diff => 1,
        .luma => 2,
        .run => 1,
    };
}

fn maybeCreateDiff(diff: PixelDifference) ?Qoi.Chunk {
    if (diff.a != 0) return null;
    return Qoi.Chunk{ .diff = .{
        std.math.cast(i2, diff.r) orelse return null,
        std.math.cast(i2, diff.g) orelse return null,
        std.math.cast(i2, diff.b) orelse return null,
    } };
}

fn maybeCreateLuma(diff: PixelDifference) ?Qoi.Chunk {
    if (diff.a != 0) return null;
    return Qoi.Chunk{ .luma = .{
        .dg = std.math.cast(i6, diff.g) orelse return null,
        .dr_dg = std.math.cast(i4, @as(i16, diff.r) - @as(i16, diff.g)) orelse return null,
        .db_dg = std.math.cast(i4, @as(i16, diff.b) - @as(i16, diff.g)) orelse return null,
    } };
}

pub fn addPixel(self: *Encoder, p: Pixel) !void {
    // std.debug.print("\n{any}\n", .{p});
    defer self.last_pixel = p;
    defer self.recent_pixels[p.hash()] = p;

    const diff = p.subtract(self.last_pixel);

    if (diff.isZero()) {
        self.run_length += 1;
        if (self.run_length >= 62) {
            // we reached maximum so send out a run chunk
            try self.emit(Qoi.Chunk{ .run = 62 });
            self.run_length = 0;
        }
        return;
    } else if (self.run_length > 0) {
        // terminate the run
        try self.emit(Qoi.Chunk{ .run = self.run_length });
        self.run_length = 0;
        // now figure out how to encode this new pixel
    }

    // check if this pixel is in the table
    if (p.subtract(self.recent_pixels[p.hash()]).isZero()) {
        try self.emit(Qoi.Chunk{ .index = p.hash() });
        return;
    }

    // check if we can use diff
    if (maybeCreateDiff(diff)) |diff_chunk| {
        try self.emit(diff_chunk);
    } else if (maybeCreateLuma(diff)) |luma_chunk| {
        try self.emit(luma_chunk);
    } else if (diff.a == 0) {
        try self.emit(Qoi.Chunk{ .rgb = .{ p.r, p.g, p.b } });
    } else {
        try self.emit(Qoi.Chunk{ .rgba = .{ p.r, p.g, p.b, p.a } });
    }
}

pub fn addPixels(self: *Encoder, pixels: []const Pixel) !void {
    for (pixels) |p| {
        try self.addPixel(p);
    }
}

/// must be called once at the end of the image
pub fn terminate(self: *Encoder) !void {
    if (self.run_length > 0) {
        try self.emit(Qoi.Chunk{ .run = self.run_length });
        self.run_length = 0;
    }
}
