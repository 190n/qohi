const std = @import("std");

pub const Chunk = union(enum) {
    rgb: [3]u8,
    rgba: [4]u8,
    index: u6,
    diff: [3]i2,
    luma: struct {
        dg: i6,
        dr_dg: i4,
        db_dg: i4,
    },
    run: u6,

    pub fn toSymbols(self: *const Chunk, buf: *[5]Symbol) []Symbol {
        switch (self.*) {
            .rgb => |channels| {
                buf[0] = Symbol.rgb;
                for (channels, 1..) |x, i| {
                    buf[i] = Symbol{ .integer = x };
                }
                return buf[0..4];
            },
            .rgba => |channels| {
                buf[0] = Symbol.rgba;
                for (channels, 1..) |x, i| {
                    buf[i] = Symbol.integer(x);
                }
                return buf[0..5];
            },
            .index => |index| {
                buf[0] = Symbol.index;
                buf[1] = Symbol.integer(index);
                return buf[0..2];
            },
            .diff => |diffs| {
                buf[0] = Symbol.diff;
                for (diffs, 1..) |x, i| {
                    buf[i] = Symbol.integer(x);
                }
                return buf[0..4];
            },
            .luma => |luma| {
                buf[0] = Symbol.luma;
                inline for (&.{ "dg", "dr_dg", "db_dg" }, 1..) |name, i| {
                    buf[i] = Symbol.integer(@field(luma, name));
                }
                return buf[0..4];
            },
            .run => |len| {
                buf[0] = Symbol.run;
                buf[1] = Symbol.integer(len);
                return buf[0..2];
            },
        }
    }
};

pub const Symbol = union(enum) {
    rgb: void,
    rgba: void,
    index: void,
    diff: void,
    luma: void,
    run: void,
    integer: i9,

    pub fn integer(x: i9) Symbol {
        return Symbol{ .integer = x };
    }
};

pub const Histogram = struct {
    histogram: [512 + 6]u64,

    pub fn init() Histogram {
        return .{ .histogram = [_]u64{0} ** (512 + 6) };
    }

    fn getIndex(symbol: Symbol) u16 {
        return switch (symbol) {
            .rgb => 0,
            .rgba => 1,
            .index => 2,
            .diff => 3,
            .luma => 4,
            .run => 5,
            .integer => |x| @intCast(u16, @as(i16, x) + 256 + 6),
        };
    }

    pub fn increment(self: *Histogram, symbol: Symbol) void {
        self.histogram[getIndex(symbol)] += 1;
    }

    pub fn count(self: *const Histogram, symbol: Symbol) u64 {
        return self.histogram[getIndex(symbol)];
    }

    pub fn iterator(self: *const Histogram) Iterator {
        return .{ .histogram = self };
    }

    pub const Iterator = struct {
        histogram: *const Histogram,
        index: u16 = 0,

        pub fn next(self: *Iterator) ?struct { Symbol, u64 } {
            if (self.index >= self.histogram.histogram.len) {
                return null;
            }
            while (self.histogram.histogram[self.index] == 0) {
                self.index += 1;
                if (self.index >= self.histogram.histogram.len) {
                    return null;
                }
            }
            const sym = switch (self.index) {
                0 => Symbol.rgb,
                1 => Symbol.rgba,
                2 => Symbol.index,
                3 => Symbol.diff,
                4 => Symbol.luma,
                5 => Symbol.run,
                else => |x| Symbol.integer(@intCast(i9, @intCast(i16, x) - 256 - 6)),
            };
            const occurrences = self.histogram.histogram[self.index];
            self.index += 1;
            return .{ sym, occurrences };
        }
    };
};

test "Chunk.toSymbols" {
    const chunks = [_]Chunk{
        .{ .rgb = .{ 1, 2, 3 } },
        .{ .rgba = .{ 1, 2, 3, 4 } },
        .{ .index = 50 },
        .{ .diff = .{ -1, 0, 1 } },
        .{ .luma = .{ .dg = 10, .dr_dg = 5, .db_dg = 3 } },
        .{ .run = 30 },
    };

    const integer = Symbol.integer;

    const symbol_strings = [_][]const Symbol{
        &.{ .rgb, integer(1), integer(2), integer(3) },
        &.{ .rgba, integer(1), integer(2), integer(3), integer(4) },
        &.{ .index, integer(50) },
        &.{ .diff, integer(-1), integer(0), integer(1) },
        &.{ .luma, integer(10), integer(5), integer(3) },
        &.{ .run, integer(30) },
    };

    for (chunks, symbol_strings) |c, ss| {
        var buf: [5]Symbol = undefined;
        try std.testing.expectEqualSlices(Symbol, ss, c.toSymbols(&buf));
    }
}

test "Histogram" {
    var h = Histogram.init();
    for (0..256) |x| {
        try std.testing.expectEqual(@as(u64, 0), h.count(Symbol.integer(@intCast(i9, x))));
    }

    h.increment(Symbol.integer(3));
    h.increment(Symbol.run);
    h.increment(Symbol.run);
    h.increment(Symbol.integer(-256));
    h.increment(Symbol.integer(-256));
    h.increment(Symbol.integer(-256));
    h.increment(Symbol.integer(255));

    try std.testing.expectEqual(@as(u64, 1), h.count(Symbol.integer(3)));
    try std.testing.expectEqual(@as(u64, 2), h.count(Symbol.run));
    try std.testing.expectEqual(@as(u64, 3), h.count(Symbol.integer(-256)));
    try std.testing.expectEqual(@as(u64, 1), h.count(Symbol.integer(255)));

    var want_to_see = std.AutoHashMap(Symbol, u64).init(std.testing.allocator);
    defer want_to_see.deinit();
    try want_to_see.put(Symbol.integer(3), 1);
    try want_to_see.put(Symbol.run, 2);
    try want_to_see.put(Symbol.integer(-256), 3);
    try want_to_see.put(Symbol.integer(255), 1);

    var it = h.iterator();
    while (it.next()) |entry| {
        try std.testing.expect(want_to_see.contains(entry[0]));
        try std.testing.expectEqual(want_to_see.get(entry[0]), entry[1]);
        try want_to_see.put(entry[0], 0);
    }

    var hash_it = want_to_see.iterator();
    while (hash_it.next()) |entry| {
        try std.testing.expectEqual(@as(u64, 0), entry.value_ptr.*);
    }
}
