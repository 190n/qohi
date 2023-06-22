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
};

fn compareNodes(context: void, a: *Node, b: *Node) std.math.Order {
    _ = context;
    return std.math.order(a.weight, b.weight);
}

pub fn createTree(allocator: std.mem.Allocator, histogram: *const Qoi.Histogram) !*Node {
    var pq = std.PriorityQueue(*Node, void, compareNodes).init(allocator, {});
    defer pq.deinit();

    var it = histogram.iterator();
    while (it.next()) |entry| {
        try pq.add(try Node.init(allocator, entry[0], entry[1]));
    }

    // ensure we have at least 2 unique symbols
    var i: i9 = 0;
    while (pq.len < 2) : (i += 1) {
        try pq.add(try Node.init(allocator, Qoi.Symbol.integer(i), 1));
    }

    while (pq.len > 1) {
        const left = pq.remove();
        const right = pq.remove();
        const parent = try Node.join(allocator, left, right);
        try pq.add(parent);
    }

    return pq.remove();
}

fn getCompressedSizeInternal(tree: *const Node, histogram: *const Qoi.Histogram, code_length: u64) u64 {
    var size: u64 = 0;
    if (tree.left) |left| {
        size += getCompressedSizeInternal(left, histogram, code_length + 1);
    }
    if (tree.right) |right| {
        size += getCompressedSizeInternal(right, histogram, code_length + 1);
    }
    if (tree.symbol) |symbol| {
        size += code_length * histogram.count(symbol);
    }
    return size;
}

pub fn getCompressedSize(tree: *const Node, histogram: *const Qoi.Histogram) u64 {
    return getCompressedSizeInternal(tree, histogram, 0);
}

test "createTree" {
    const tree = try createTree(std.testing.allocator, &Qoi.Histogram.init());
    defer tree.deinit(std.testing.allocator);
}
