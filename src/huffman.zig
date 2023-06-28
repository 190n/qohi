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

pub fn createTree(
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
            .code = self.code | @as(u64, bit) << @intCast(u6, self.len),
            .len = self.len + 1,
        };
    }

    pub fn format(self: Code, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        for (0..self.len) |i| {
            const bit: u8 = @truncate(u1, self.code >> @intCast(u6, i));
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
            writeTree(WriterType, bw, left);
            writeTree(WriterType, bw, right);
            try bw.writeBits(0, 1);
        }
    } else if (tree.symbol) |symbol| {
        try bw.writeBits(1, 1);
        try symbol.writeTo(WriterType, bw);
    }
}
