const std = @import("std");
const Qoi = @import("./qoi.zig");

pub const Node = struct {
    weight: u64 = 0,
    symbol: ?Qoi.Symbol = null,
    left: ?*Node = null,
    right: ?*Node = null,

    pub fn init(allocator: std.mem.Allocator, symbol: ?Qoi.Symbol, weight: u64) !*Node {
        const node = try allocator.create(Node);
        node.* = .{ .symbol = symbol, .weight = weight };
        return node;
    }

    pub fn join(allocator: std.mem.Allocator, left: *Node, right: *Node) !*Node {
        const node = try Node.init(allocator, null, left.weight + right.weight);
        node.left = left;
        node.right = right;
        return node;
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        if (self.left) |left| {
            left.deinit(allocator);
        }
        if (self.right) |right| {
            right.deinit(allocator);
        }
        self.* = undefined;
        allocator.destroy(self);
    }

    pub fn compare(context: void, a: *const Node, b: *const Node) std.math.Order {
        _ = context;
        return std.math.order(a.weight, b.weight);
    }

    fn expectStructureEquals(expected: *const Node, actual: *const Node) !void {
        try std.testing.expectEqual(expected.symbol, actual.symbol);
        if (expected.left) |left| {
            try std.testing.expect(actual.left != null);
            try expectStructureEquals(left, actual.left.?);
        } else {
            try std.testing.expectEqual(@as(?*Node, null), actual.left);
        }
        if (expected.right) |right| {
            try std.testing.expect(actual.right != null);
            try expectStructureEquals(right, actual.right.?);
        } else {
            try std.testing.expectEqual(@as(?*Node, null), actual.right);
        }
    }
};

const NodePq = std.PriorityQueue(*Node, void, Node.compare);

fn ensureAtLeast2(pq: *NodePq, allocator: std.mem.Allocator) !void {
    var i: u8 = 0;
    while (pq.len < 2) : (i += 1) {
        try pq.add(try Node.init(allocator, Qoi.Symbol.integer(i), 0));
    }
}

fn consumeAndJoin(pq: *NodePq, allocator: std.mem.Allocator) !void {
    while (pq.len > 1) {
        const left = pq.remove();
        const right = pq.remove();
        const parent = try Node.join(allocator, left, right);
        try pq.add(parent);
    }
}

pub const Trees = struct {
    symbol_tree: *Node,
    integer_tree: *Node,

    pub fn deinit(self: *Trees, allocator: std.mem.Allocator) void {
        self.symbol_tree.deinit(allocator);
        self.integer_tree.deinit(allocator);
        self.* = undefined;
    }
};

pub fn createTrees(
    allocator: std.mem.Allocator,
    histogram: *const std.AutoHashMap(Qoi.Symbol, u64),
) !Trees {
    var pq1 = NodePq.init(allocator, {});
    defer pq1.deinit();
    var pq2 = NodePq.init(allocator, {});
    defer pq2.deinit();

    var it = histogram.iterator();
    while (it.next()) |entry| {
        const queue_to_use = switch (entry.key_ptr.*) {
            .integer => &pq2,
            else => &pq1,
        };
        try queue_to_use.add(try Node.init(allocator, entry.key_ptr.*, entry.value_ptr.*));
    }

    inline for (.{ &pq1, &pq2 }) |pq| {
        try ensureAtLeast2(pq, allocator);
        try consumeAndJoin(pq, allocator);
    }

    return .{ .symbol_tree = pq1.remove(), .integer_tree = pq2.remove() };
}

fn getCompressedSizeInternal(
    tree: *const Node,
    histogram: *const std.AutoHashMap(Qoi.Symbol, u64),
    code_length: u6,
) u64 {
    var size: u64 = 0;
    if (tree.left) |left| {
        size += getCompressedSizeInternal(left, histogram, code_length + 1);
    }
    if (tree.right) |right| {
        size += getCompressedSizeInternal(right, histogram, code_length + 1);
    }
    if (tree.symbol) |_| {
        size += code_length * tree.weight;
    }
    return size;
}

pub fn getCompressedSize(
    trees: Trees,
    histogram: *const std.AutoHashMap(Qoi.Symbol, u64),
) u64 {
    var size = getCompressedSizeInternal(trees.symbol_tree, histogram, 0);
    size += getCompressedSizeInternal(trees.integer_tree, histogram, 0);

    var counter = std.io.countingWriter(std.io.null_writer);
    var bw = std.io.bitWriter(.Big, counter.writer());
    try writeTree(@TypeOf(counter.writer()), &bw, trees.symbol_tree);
    try bw.flushBits();

    bw = std.io.bitWriter(.Big, counter.writer());
    try writeTree(@TypeOf(counter.writer()), &bw, trees.integer_tree);
    try bw.flushBits();

    size += counter.bytes_written;

    return size;
}

pub const Code = struct {
    code: u64,
    len: u6,

    pub fn init() Code {
        return .{ .code = 0, .len = 0 };
    }

    pub fn push(self: Code, bit: u1) Code {
        std.debug.assert(self.len < std.math.maxInt(@TypeOf(self.len)));
        return .{
            .code = self.code | @as(u64, bit) << @intCast(self.len),
            .len = self.len + 1,
        };
    }

    pub fn format(self: Code, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        for (0..self.len) |i| {
            const bit: u8 = @as(u1, @truncate(self.code >> @intCast(i)));
            try writer.writeByte(bit + '0');
        }
    }
};

fn buildCodeTableInternal(tree: *const Node, table: *std.AutoHashMap(Qoi.Symbol, Code), prefix: Code) !void {
    if (tree.left) |left| {
        try buildCodeTableInternal(left, table, prefix.push(0));
    }
    if (tree.right) |right| {
        try buildCodeTableInternal(right, table, prefix.push(1));
    }
    if (tree.symbol) |symbol| {
        try table.putNoClobber(symbol, prefix);
    }
}

pub fn buildCodeTable(allocator: std.mem.Allocator, tree: *const Node) !std.AutoHashMap(Qoi.Symbol, Code) {
    var table = std.AutoHashMap(Qoi.Symbol, Code).init(allocator);
    try buildCodeTableInternal(tree, &table, Code.init());
    return table;
}

pub fn writeTree(
    comptime WriterType: type,
    bw: *std.io.BitWriter(.Big, WriterType),
    tree: *const Node,
) !void {
    if (tree.left) |left| {
        if (tree.right) |right| {
            try writeTree(WriterType, bw, left);
            try writeTree(WriterType, bw, right);
            try bw.writeBits(@as(u1, 0), 1);
        }
    } else if (tree.symbol) |symbol| {
        try bw.writeBits(@as(u1, 1), 1);
        try symbol.writeTo(WriterType, bw);
    }
}

pub fn rebuildTree(
    allocator: std.mem.Allocator,
    comptime ReaderType: type,
    br: *std.io.BitReader(.Big, ReaderType),
    num_leaves: u16,
    int_symbols: bool,
) !*Node {
    var stack = std.ArrayList(*Node).init(allocator);
    defer stack.deinit();
    errdefer for (stack.items) |n| {
        n.deinit(allocator);
    };
    const num_nodes = 2 * num_leaves - 1;

    for (0..num_nodes) |_| {
        const bit = try br.readBitsNoEof(u1, 1);
        if (bit == 1) {
            // read a symbol
            const new_node = try Node.init(
                allocator,
                if (int_symbols)
                    Qoi.Symbol.integer(try br.readBitsNoEof(u8, 8))
                else
                    try Qoi.Symbol.readFrom(ReaderType, br),
                0,
            );
            errdefer new_node.deinit(allocator);
            try stack.append(new_node);
        } else {
            // create an interior node
            const joined = blk: {
                const right = stack.popOrNull() orelse return error.InvalidFile;
                errdefer right.deinit(allocator);
                const left = stack.popOrNull() orelse return error.InvalidFile;
                errdefer left.deinit(allocator);
                break :blk try Node.join(allocator, left, right);
            };
            errdefer joined.deinit(allocator);
            try stack.append(joined);
        }
    }

    if (stack.items.len != 1) return error.InvalidFile;
    return stack.pop();
}

fn rebuildTreeThenFree(
    allocator: std.mem.Allocator,
    buffer: []const u8,
    num_leaves: u16,
    int_symbols: bool,
) !void {
    var buf_stream = std.io.fixedBufferStream(buffer);
    var br = std.io.bitReader(.Big, buf_stream.reader());
    const tree = try rebuildTree(allocator, std.io.FixedBufferStream([]const u8).Reader, &br, num_leaves, int_symbols);
    tree.deinit(allocator);
}

test "write/rebuildTree round-trip" {
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();
    var histogram = std.AutoHashMap(Qoi.Symbol, u64).init(std.testing.allocator);
    defer histogram.deinit();

    try histogram.put(Qoi.Symbol.rgb, 5);
    try histogram.put(Qoi.Symbol.luma(20), 3);
    try histogram.put(Qoi.Symbol.run(128), 10);
    try histogram.put(Qoi.Symbol.diff, 50);
    try histogram.put(Qoi.Symbol.index(3), 2);
    try histogram.put(Qoi.Symbol.integer(200), 30);
    try histogram.put(Qoi.Symbol.integer(9), 20);
    try histogram.put(Qoi.Symbol.integer(8), 10);
    try histogram.put(Qoi.Symbol.integer(0), 300);
    try histogram.put(Qoi.Symbol.integer(20), 5);
    var trees = try createTrees(std.testing.allocator, &histogram);
    defer trees.deinit(std.testing.allocator);

    // symbol tree
    var bw = std.io.bitWriter(.Big, output.writer());
    try writeTree(std.ArrayList(u8).Writer, &bw, trees.symbol_tree);
    try bw.flushBits();

    var buf_stream = std.io.fixedBufferStream(output.items);
    var br = std.io.bitReader(.Big, buf_stream.reader());
    const new_symbol_tree = try rebuildTree(
        std.testing.allocator,
        std.io.FixedBufferStream([]u8).Reader,
        &br,
        5,
        false,
    );
    defer new_symbol_tree.deinit(std.testing.allocator);
    try Node.expectStructureEquals(trees.symbol_tree, new_symbol_tree);

    try std.testing.checkAllAllocationFailures(std.testing.allocator, rebuildTreeThenFree, .{
        output.items,
        5,
        false,
    });

    // integer tree
    output.clearRetainingCapacity();
    bw = std.io.bitWriter(.Big, output.writer());
    try writeTree(std.ArrayList(u8).Writer, &bw, trees.integer_tree);
    try bw.flushBits();

    buf_stream = std.io.fixedBufferStream(output.items);
    br = std.io.bitReader(.Big, buf_stream.reader());
    const new_integer_tree = try rebuildTree(
        std.testing.allocator,
        std.io.FixedBufferStream([]u8).Reader,
        &br,
        5,
        true,
    );
    defer new_integer_tree.deinit(std.testing.allocator);
    try Node.expectStructureEquals(trees.integer_tree, new_integer_tree);

    try std.testing.checkAllAllocationFailures(std.testing.allocator, rebuildTreeThenFree, .{
        output.items,
        5,
        true,
    });
}
