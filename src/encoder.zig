const std = @import("std");
const Encoder = @This();

const Pixel = @import("./pixel.zig").Pixel;
const PixelDifference = @import("./pixel.zig").PixelDifference;
const Qoi = @import("./qoi.zig");

last_pixel: Pixel = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
recent_pixels: [256]Pixel = .{.{ .r = 0, .g = 0, .b = 0, .a = 0 }} ** 256,
run_length: u8 = 0,
histogram: std.AutoHashMap(Qoi.Symbol, u64),
symbols: std.ArrayList(Qoi.Symbol),
total_qoi_size: usize = 0,

pub fn init(allocator: std.mem.Allocator) Encoder {
    return .{
        .histogram = std.AutoHashMap(Qoi.Symbol, u64).init(allocator),
        .symbols = std.ArrayList(Qoi.Symbol).init(allocator),
    };
}

pub fn deinit(self: *Encoder) void {
    self.histogram.deinit();
    self.symbols.deinit();
    self.* = undefined;
}

fn emit(self: *Encoder, chunk: Qoi.Chunk) !void {
    var buf: [5]Qoi.Symbol = undefined;
    const syms = chunk.toSymbols(&buf);

    for (syms) |s| {
        const entry = try self.histogram.getOrPut(s);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
        try self.symbols.append(s);
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

    const DiffType = std.meta.Child(std.meta.FieldType(Qoi.Chunk, .diff));
    return Qoi.Chunk{ .diff = .{
        std.math.cast(DiffType, diff.r) orelse return null,
        std.math.cast(DiffType, diff.g) orelse return null,
        std.math.cast(DiffType, diff.b) orelse return null,
    } };
}

fn maybeCreateLuma(diff: PixelDifference) ?Qoi.Chunk {
    if (diff.a != 0) return null;

    const DgType = std.meta.FieldType(std.meta.FieldType(Qoi.Chunk, .luma), .dg);
    const OffsetType = std.meta.FieldType(std.meta.FieldType(Qoi.Chunk, .luma), .dr_dg);

    return Qoi.Chunk{ .luma = .{
        .dg = std.math.cast(DgType, diff.g) orelse return null,
        .dr_dg = std.math.cast(OffsetType, @as(i16, diff.r) - @as(i16, diff.g)) orelse return null,
        .db_dg = std.math.cast(OffsetType, @as(i16, diff.b) - @as(i16, diff.g)) orelse return null,
    } };
}

pub fn addPixel(self: *Encoder, p: Pixel) !void {
    defer self.last_pixel = p;
    defer self.recent_pixels[p.hash()] = p;

    const diff = p.subtract(self.last_pixel);

    if (diff.isZero()) {
        const max_run_length = std.math.maxInt(@TypeOf(self.run_length));
        if (self.run_length == max_run_length) {
            // we reached maximum so send out a run chunk
            try self.emit(Qoi.Chunk{ .run = max_run_length });
            self.run_length = 0;
        } else {
            self.run_length += 1;
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
