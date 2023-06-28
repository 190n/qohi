const std = @import("std");
const stb_image = @cImport({
    @cInclude("stb_image.h");
});

const max_align = @import("builtin").target.maxIntAlignment();
const pad_amount = std.mem.alignForward(usize, @sizeOf(usize), max_align);

/// which allocator stb_image functions will use. defaults to the C allocator.
/// if you set this, only do so once and before you call any stb_image functions.
pub var allocator = std.heap.c_allocator;

export fn stbiMalloc(size: usize) ?[*]align(max_align) u8 {
    const slice = allocator.alignedAlloc(u8, max_align, pad_amount + size) catch return null;
    // store the size before the data
    @ptrCast(*usize, slice.ptr).* = size;
    return slice.ptr + pad_amount;
}

export fn stbiRealloc(maybe_ptr: ?[*]align(max_align) u8, new_size: usize) ?[*]align(max_align) u8 {
    if (maybe_ptr) |ptr| {
        const orig_ptr = ptr - pad_amount;
        const orig_size = @ptrCast(*const usize, orig_ptr).*;
        const orig_slice = orig_ptr[0..(pad_amount + orig_size)];
        // realloc will take the alignment from the type of the old slice which is why we don't have
        // "aligned realloc" here or anything
        const new_slice = allocator.realloc(orig_slice, pad_amount + new_size) catch return null;
        @ptrCast(*usize, new_slice.ptr).* = new_size;
        return new_slice.ptr + pad_amount;
    } else return stbiMalloc(new_size);
}

export fn stbiFree(maybe_ptr: ?[*]align(max_align) u8) void {
    // free(NULL) should work and do nothing
    if (maybe_ptr) |ptr| {
        const orig_ptr = ptr - pad_amount;
        const orig_size = @ptrCast(*const usize, orig_ptr).*;
        const orig_slice = orig_ptr[0..(pad_amount + orig_size)];
        allocator.free(orig_slice);
    }
}

pub const Image = struct {
    /// pointer to color data; length = x * y * channels
    data: []u8,
    /// width of the image
    x: usize,
    /// height of the image
    y: usize,
    /// how many channels are in the returned buffer
    channels: Channels,
    /// how many channels are in the file
    channels_in_file: Channels,

    /// free the buffer
    pub fn deinit(self: *Image) void {
        stb_image.stbi_image_free(self.data.ptr);
        self.* = undefined;
    }
};

pub const Channels = enum(u3) {
    grey = 1,
    grey_alpha = 2,
    rgb = 3,
    rgba = 4,
};

fn makeCallbacks(comptime ContextPtr: type) stb_image.stbi_io_callbacks {
    const callbacks = struct {
        fn opaqueToContext(user: ?*anyopaque) ContextPtr {
            return @ptrCast(ContextPtr, @alignCast(@alignOf(@typeInfo(ContextPtr).Pointer.child), user));
        }

        pub fn read(user: ?*anyopaque, data: ?[*]u8, size: c_int) callconv(.C) c_int {
            const context = opaqueToContext(user);
            return @intCast(c_int, context.reader().read(data.?[0..@intCast(usize, size)]) catch 0);
        }

        pub fn skip(user: ?*anyopaque, n: c_int) callconv(.C) void {
            const context = opaqueToContext(user);
            context.seekableStream().seekBy(n) catch unreachable;
        }

        pub fn eof(user: ?*anyopaque) callconv(.C) c_int {
            const context = opaqueToContext(user);
            var byte: [1]u8 = undefined;
            // errors are counted as EOF because continuing to read probably isn't desired, and
            // stb_image will already report errors from too-early EOFs that cause files to be
            // invalid
            const amount_read = context.reader().read(&byte) catch return 1;
            if (amount_read == 0) {
                // nothing read means EOF
                return 1;
            } else {
                // skip back, and now we're not at EOF
                context.seekableStream().seekBy(-1) catch return 1;
                return 0;
            }
        }
    };

    return .{
        .read = callbacks.read,
        .skip = callbacks.skip,
        .eof = callbacks.eof,
    };
}

/// load an image using stbi_image
/// stream_ptr:       pointer to some I/O stream (supporting .reader() and .seekableStream())
/// desired_channels: if null, the returned buffer has as many channels in it as were actually in
///                   the image. if non-null, stb_image will convert it to the number of channels
///                   you asked for.
/// error_ptr:        if non-null and error occurs, set to point to error message
/// call .deinit() on the result when you are done
pub fn load(stream_ptr: anytype, desired_channels: ?Channels, error_ptr: ?*[:0]const u8) !Image {
    var x: c_int = undefined;
    var y: c_int = undefined;
    var channels_in_file: c_int = undefined;
    const callbacks = makeCallbacks(@TypeOf(stream_ptr));
    const result: ?[*]u8 = stb_image.stbi_load_from_callbacks(
        &callbacks,
        // possibly cast away constness -- this is okay as stb_image itself doesn't modify the user
        // pointer, it only passes it (as void *) to functions that might modify it, but we will
        // cast back to a const pointer if stream_ptr was originally const.
        @constCast(stream_ptr),
        &x,
        &y,
        &channels_in_file,
        if (desired_channels) |dc| @intFromEnum(dc) else 0,
    );

    if (result) |ptr| {
        const actual_channels = if (desired_channels) |dc| @intFromEnum(dc) else @intCast(u3, channels_in_file);
        return Image{
            .data = ptr[0..(@intCast(usize, x) * @intCast(usize, y) * actual_channels)],
            .x = @intCast(usize, x),
            .y = @intCast(usize, y),
            .channels = @enumFromInt(Channels, actual_channels),
            .channels_in_file = @enumFromInt(Channels, channels_in_file),
        };
    } else {
        if (error_ptr) |ptr| {
            ptr.* = std.mem.span(@ptrCast([*:0]const u8, stb_image.stbi_failure_reason()));
        }
        return error.StbImageError;
    }
}

test "I/O callbacks" {
    allocator = std.testing.allocator;
    const cbs = makeCallbacks(*std.io.FixedBufferStream([]const u8));
    const in_buf = "hello world";
    var out_buf: [in_buf.len]u8 = undefined;
    var stream = std.io.fixedBufferStream(in_buf);

    // it should read 5 bytes and not be at EOF
    try std.testing.expectEqual(@as(c_int, 5), cbs.read.?(&stream, &out_buf, 5));
    try std.testing.expectEqualSlices(u8, "hello", out_buf[0..5]);
    try std.testing.expectEqual(@as(c_int, 0), cbs.eof.?(&stream));

    // it should read 6 bytes and be at EOF
    try std.testing.expectEqual(@as(c_int, 6), cbs.read.?(&stream, &out_buf, out_buf.len));
    try std.testing.expectEqualSlices(u8, " world", out_buf[0..6]);
    try std.testing.expect(cbs.eof.?(&stream) != 0);

    // it should read zero bytes and still be at EOF
    try std.testing.expectEqual(@as(c_int, 0), cbs.read.?(&stream, &out_buf, out_buf.len));
    try std.testing.expect(cbs.eof.?(&stream) != 0);

    // it should seek back, then not be at EOF, then read 3 bytes and return to EOF
    cbs.skip.?(&stream, -3);
    try std.testing.expectEqual(@as(c_int, 0), cbs.eof.?(&stream));
    try std.testing.expectEqual(@as(c_int, 3), cbs.read.?(&stream, &out_buf, out_buf.len));
    try std.testing.expectEqualSlices(u8, "rld", out_buf[0..3]);
    try std.testing.expect(cbs.eof.?(&stream) != 0);
}

test "image loading with specified channels" {
    allocator = std.testing.allocator;
    const png = @embedFile("./test_image.png");
    var stream = std.io.fixedBufferStream(png);
    // file is RGB, but 4 should make it generate an alpha channel for us
    var result = try load(&stream, .rgba, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 3), result.x);
    try std.testing.expectEqual(@as(usize, 2), result.y);
    try std.testing.expectEqual(Channels.rgba, result.channels);
    try std.testing.expectEqual(Channels.rgb, result.channels_in_file);
    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xFF, 0x00, 0x00, 0xFF, // red
        0x00, 0xFF, 0x00, 0xFF, // green
        0x00, 0x00, 0xFF, 0xFF, // blue
        0x00, 0xFF, 0xFF, 0xFF, // cyan
        0xFF, 0x00, 0xFF, 0xFF, // magenta
        0xFF, 0xFF, 0x00, 0xFF, // yellow
    }, result.data);
}

test "image loading with unspecified channels" {
    allocator = std.testing.allocator;
    const png = @embedFile("./test_image.png");
    var stream = std.io.fixedBufferStream(png);
    var result = try load(&stream, null, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 3), result.x);
    try std.testing.expectEqual(@as(usize, 2), result.y);
    try std.testing.expectEqual(Channels.rgb, result.channels);
    try std.testing.expectEqual(Channels.rgb, result.channels_in_file);
    try std.testing.expectEqualSlices(u8, &[_]u8{
        0xFF, 0x00, 0x00, // red
        0x00, 0xFF, 0x00, // green
        0x00, 0x00, 0xFF, // blue
        0x00, 0xFF, 0xFF, // cyan
        0xFF, 0x00, 0xFF, // magenta
        0xFF, 0xFF, 0x00, // yellow
    }, result.data);
}

test "unsuccessful image loading" {
    allocator = std.testing.allocator;
    const buf = [_]u8{ 1, 2, 3, 4, 5 };
    var stream = std.io.fixedBufferStream(&buf);
    var err: [:0]const u8 = undefined;
    try std.testing.expectError(error.StbImageError, load(&stream, null, &err));
    try std.testing.expectEqualSlices(u8, "Image not of any known type, or corrupt", err);
}
