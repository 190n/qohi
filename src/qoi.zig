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
                    buf[i] = Symbol.integer(@bitCast(@as(i8, x)));
                }
                return buf[0..4];
            },
            .luma => |luma| {
                buf[0] = Symbol.luma(luma.dg);
                buf[1] = Symbol.integer(@bitCast(luma.dr_dg));
                buf[2] = Symbol.integer(@bitCast(luma.db_dg));
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

    pub fn writeTo(self: Symbol, comptime WriterType: type, bw: *std.io.BitWriter(.Big, WriterType)) !void {
        // integer symbols are in their own tree so we don't need to distinguish that this is an
        // integer. just write the bits. other symbols (xx... = payload data):
        // index = 00  xxxxxxxx
        // luma  = 01  xxxxxxxx
        // run   = 100 xxxxxxxx
        // rgb   = 101
        // rgba  = 110
        // diff  = 111
        switch (self) {
            .integer => |int| try bw.writeBits(int, 8),
            .index => |i| {
                try bw.writeBits(@as(u2, 0b00), 2);
                try bw.writeBits(i, 8);
            },
            .luma => |dg| {
                try bw.writeBits(@as(u2, 0b01), 2);
                try bw.writeBits(@as(u8, @bitCast(dg)), 8);
            },
            .run => |len| {
                try bw.writeBits(@as(u3, 0b100), 3);
                try bw.writeBits(len, 8);
            },
            .rgb => try bw.writeBits(@as(u3, 0b101), 3),
            .rgba => try bw.writeBits(@as(u3, 0b110), 3),
            .diff => try bw.writeBits(@as(u3, 0b111), 3),
        }
    }

    /// this never returns Symbol.integer, since that is in its own tree and you just read 8 bits
    pub fn readFrom(comptime ReaderType: type, br: *std.io.BitReader(.Big, ReaderType)) !Symbol {
        const first = try br.readBitsNoEof(u1, 1);
        if (first == 0) {
            const second = try br.readBitsNoEof(u1, 1);
            return switch (second) {
                0 => Symbol.index(try br.readBitsNoEof(u8, 8)),
                1 => Symbol.luma(@bitCast(try br.readBitsNoEof(u8, 8))),
            };
        } else {
            const rest = try br.readBitsNoEof(u2, 2);
            return switch (rest) {
                0b00 => Symbol.run(try br.readBitsNoEof(u8, 8)),
                0b01 => Symbol.rgb,
                0b10 => Symbol.rgba,
                0b11 => Symbol.diff,
            };
        }
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

    const integer = Symbol.integer;

    const symbol_strings = [_][]const Symbol{
        &.{ Symbol.rgb, integer(1), integer(2), integer(3) },
        &.{ Symbol.rgba, integer(1), integer(2), integer(3), integer(4) },
        &.{Symbol.index(50)},
        &.{ Symbol.diff, integer(255), integer(0), integer(1) },
        &.{ Symbol.luma(10), integer(5), integer(3) },
        &.{Symbol.run(30)},
    };

    for (chunks, symbol_strings) |c, ss| {
        var buf: [5]Symbol = undefined;
        const actual = c.toSymbols(&buf);
        try std.testing.expectEqualSlices(Symbol, ss, actual);
    }
}

const testing_symbols = [_]Symbol{
    Symbol.rgb, Symbol.rgba, Symbol.index(0), Symbol.luma(0b110), Symbol.diff,
};

test "Symbol.writeTo" {
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    var bw = std.io.bitWriter(.Big, output.writer());
    for (testing_symbols) |sym| {
        try sym.writeTo(std.ArrayList(u8).Writer, &bw);
    }
    try Symbol.integer(0b11000101).writeTo(std.ArrayList(u8).Writer, &bw);
    try bw.flushBits();

    try std.testing.expectEqualSlices(
        u8,
        &.{ 0b10111000, 0b00000000, 0b01000001, 0b10111110, 0b00101000 },
        output.items,
    );
}

test "Symbol.readFrom" {
    var input = std.io.fixedBufferStream(&[_]u8{ 0b10111000, 0b00000000, 0b01000001, 0b10111000 });
    var br = std.io.bitReader(.Big, input.reader());
    for (testing_symbols) |sym| {
        try std.testing.expectEqual(sym, try Symbol.readFrom(std.io.FixedBufferStream([]const u8).Reader, &br));
    }
}

test "Symbol I/O round-trip" {
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    var bw = std.io.bitWriter(.Big, output.writer());
    for (testing_symbols) |sym| {
        try sym.writeTo(std.ArrayList(u8).Writer, &bw);
    }
    try bw.flushBits();

    var reader = std.io.fixedBufferStream(output.items);
    var br = std.io.bitReader(.Big, reader.reader());

    for (testing_symbols) |sym| {
        try std.testing.expectEqual(sym, try Symbol.readFrom(@TypeOf(reader.reader()), &br));
    }
}
