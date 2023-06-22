const std = @import("std");
const yazap = @import("yazap");

const StbImage = @import("./stb_image.zig");
const Encoder = @import("./encoder.zig");
const Pixel = @import("./pixel.zig").Pixel;
const Huffman = @import("./huffman.zig");

const App = yazap.App;
const Arg = yazap.Arg;

pub fn main() !void {
    const allocator = std.heap.c_allocator;
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
    } else {
        std.debug.print(
            "{}x{}, {} channels\n",
            .{ image.ok.x, image.ok.y, @enumToInt(image.ok.channels_in_file) },
        );
    }

    const pixels = @ptrCast([*]const Pixel, image.ok.data.ptr)[0..(image.ok.x * image.ok.y)];
    var e = Encoder.init(allocator);
    defer e.deinit();
    try e.addPixels(pixels);
    try e.terminate();

    std.debug.print("size as regular QOI: {}\n", .{e.total_qoi_size});
    const tree = try Huffman.createTree(allocator, &e.histogram);
    defer tree.deinit(allocator);
    std.debug.print("size with huffman: {}\n", .{try std.math.divCeil(u64, Huffman.getCompressedSize(tree, &e.histogram), 8)});

    var it = e.histogram.iterator();
    while (it.next()) |entry| {
        std.debug.print("{any} => {}\n", .{ entry[0], entry[1] });
    }
}
