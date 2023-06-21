const std = @import("std");
const yazap = @import("yazap");
const StbImage = @import("./stb_image.zig");

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
    } else {
        std.debug.print("{}x{}, {} channels\n", .{ image.ok.x, image.ok.y, @enumToInt(image.ok.channels) });
    }
}
