const std = @import("std");

pub const Chunk = union(enum) {
    rgb: [3]u8,
    rgba: [4]u8,
    index: u8,
    diff: [3]i2,
    luma: struct {
        dg: i8,
        dr_dg: i8,
        db_dg: i8,
    },
    run: u8,

    pub fn toSymbols(self: *const Chunk, buf: *[5]Symbol) []Symbol {
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
                buf[0] = Symbol.index(index);
                return buf[0..1];
            },
            .diff => |diffs| {
                buf[0] = Symbol.diff;
                for (diffs, 1..) |x, i| {
                    buf[i] = Symbol.integer(@bitCast(u8, @as(i8, x)));
                }
                return buf[0..4];
            },
            .luma => |luma| {
                buf[0] = Symbol.luma(luma.dg);
                buf[1] = Symbol.integer(@bitCast(u8, luma.dr_dg));
                buf[2] = Symbol.integer(@bitCast(u8, luma.db_dg));
                return buf[0..3];
            },
            .run => |len| {
                buf[0] = Symbol.run(len);
                return buf[0..1];
            },
        }
    }
};

pub const Symbol = union(enum) {
    rgb: void,
    rgba: void,
    index: u8,
    diff: void,
    luma: i8,
    run: u8,
    integer: u8,

    pub fn integer(x: u8) Symbol {
        return Symbol{ .integer = x };
    }

    pub fn run(len: u8) Symbol {
        return Symbol{ .run = len };
    }

    pub fn luma(dg: i8) Symbol {
        return Symbol{ .luma = dg };
    }

    pub fn index(i: u8) Symbol {
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
    @panic("not a real test");
}
