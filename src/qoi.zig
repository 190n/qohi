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

    pub fn toSymbols(self: *const Chunk, buf: *[9]Symbol) []Symbol {
        switch (self.*) {
            .rgb => |channels| {
                buf[0] = Symbol.rgb;
                for (channels, 1..) |x, i| {
                    buf[i] = Symbol.integer(x);
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
                // buf[0] = Symbol.index;
                // buf[1] = Symbol.integer(index);
                // return buf[0..2];
                buf[0] = Symbol.index(index);
                return buf[0..1];
            },
            .diff => |diffs| {
                buf[0] = Symbol.diff;
                for (diffs, 1..) |x, i| {
                    buf[i] = Symbol.integer(@bitCast(u2, x));
                }
                return buf[0..4];
            },
            .luma => |luma| {
                // buf[0] = Symbol.luma;
                // inline for (&.{ "dg", "dr_dg", "db_dg" }, 1..) |name, i| {
                //     buf[i] = Symbol.integer(@field(luma, name));
                // }
                // return buf[0..4];
                buf[0] = Symbol.luma(luma.dg);
                buf[1] = Symbol.integer(@bitCast(u4, luma.dr_dg));
                buf[2] = Symbol.integer(@bitCast(u4, luma.db_dg));
                return buf[0..3];
            },
            .run => |len| {
                // buf[0] = Symbol.run;
                // buf[1] = Symbol.integer(len);
                // return buf[0..2];
                buf[0] = Symbol.run(len);
                return buf[0..1];
            },
        }
    }
};

pub const Symbol = union(enum) {
    rgb: void,
    rgba: void,
    index: u6,
    diff: void,
    luma: i6,
    run: u6,
    integer: u8,

    pub fn integer(x: u8) Symbol {
        return Symbol{ .integer = x };
    }

    pub fn run(len: u6) Symbol {
        return Symbol{ .run = len };
    }

    pub fn luma(dg: i6) Symbol {
        return Symbol{ .luma = dg };
    }

    pub fn index(i: u6) Symbol {
        return Symbol{ .index = i };
    }
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
    _ = chunks;

    const integer = Symbol.integer;
    _ = integer;

    // // const symbol_strings = [_][]const Symbol{
    // //     &.{ .rgb, integer(1), integer(2), integer(3) },
    // //     &.{ .rgba, integer(1), integer(2), integer(3), integer(4) },
    // //     &.{ .index, integer(50) },
    // //     &.{ .diff, integer(-1), integer(0), integer(1) },
    // //     &.{ .luma, integer(10), integer(5), integer(3) },
    // //     &.{ .run, integer(30) },
    // // };

    // for (chunks, symbol_strings) |c, ss| {
    //     var buf: [9]Symbol = undefined;
    //     try std.testing.expectEqualSlices(Symbol, ss, c.toSymbols(&buf));
    // }
}
