const std = @import("std");
const yazap = @import("yazap");

const StbImage = @import("./stb_image.zig");
const Encoder = @import("./encoder.zig");
const Pixel = @import("./pixel.zig").Pixel;
const Huffman = @import("./huffman.zig");

const App = yazap.App;
const Arg = yazap.Arg;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = if (std.debug.runtime_safety)
        gpa.allocator()
    else
        std.heap.c_allocator;
    defer std.debug.assert(gpa.deinit() == .ok);

    StbImage.allocator = allocator;

    var app = App.init(allocator, "qohi", null);
    defer app.deinit();

    var qohi = app.rootCommand();

    try qohi.addArg(Arg.positional("INPUT", null, null));

    const matches = try app.parseProcess();

    const input_name = matches.getSingleValue("INPUT") orelse return error.NoInputFile;
    const input_file = try std.fs.cwd().openFile(input_name, .{});

    var image = StbImage.load(&input_file, StbImage.Channels.rgba);
    defer image.deinit();

    if (image == .err) {
        std.debug.print("error opening image: {s}\n", .{image.err});
        std.process.exit(1);
    }

    const pixels = @ptrCast([*]const Pixel, image.ok.data.ptr)[0..(image.ok.x * image.ok.y)];
    var e = Encoder.init(allocator);
    defer e.deinit();
    try e.addPixels(pixels);
    try e.terminate();

    const tree = try Huffman.createTree(allocator, &e.histogram);
    defer tree.deinit(allocator);
    const huffman_size = try std.math.divCeil(u64, Huffman.getCompressedSize(tree, &e.histogram), 8);
    const uncompressed_size = image.ok.x * image.ok.y * @intFromEnum(image.ok.channels_in_file);

    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\{{
        \\    "uncompressed": {},
        \\    "qoi": {},
        \\    "huffman": {}
        \\}}
        \\
    , .{ uncompressed_size, e.total_qoi_size, huffman_size });

    // var table = try Huffman.buildCodeTable(allocator, tree);
    // defer table.deinit();
    // var it = table.iterator();
    // while (it.next()) |entry| {
    //     try stdout.print("{} {any} {}\n", .{ entry.value_ptr.*, entry.key_ptr.*, e.histogram.get(entry.key_ptr.*).? });
    // }
}
