const std = @import("std");
const uefi = std.os.uefi;
const GraphicsPixelFormat = uefi.protocols.GraphicsPixelFormat;

extern var _binary_hankaku_bin_start: u8;
extern var _binary_hankaku_bin_end: u8;
extern var _binary_hankaku_bin_size: u8;

export fn kernelMain(frame_buffer_config: *FrameBufferConfig) void {
    var pixel_writer = BGRPixelWriter.new(frame_buffer_config);

    var i: usize = 0;
    while (i < frame_buffer_config.horizontal_resolution * frame_buffer_config.vertical_resolution) : (i += 1) {
        pixel_writer.write(i % frame_buffer_config.horizontal_resolution, i / frame_buffer_config.horizontal_resolution, &PixelColor.black);
    }

    const hello_world = "Hello, World!";
    var pos: u32 = 0;
    inline for (hello_world) |c| {
        pixel_writer.writeAscii(pos, 0, c, &PixelColor.white);
        pos += 8;
    }

    const desc = "This kernel code is written in Zig language!";
    pos = 0;
    inline for (desc) |c| {
        pixel_writer.writeAscii(pos, 16, c, &PixelColor.white);
        pos += 8;
    }
    halt();
}

const FrameBufferConfig = extern struct {
    frame_buffer: [*]u8,
    pixels_per_scan_line: u32,
    horizontal_resolution: u32,
    vertical_resolution: u32,
    pixel_format: GraphicsPixelFormat,
};

const PixelColor = struct {
    r: u8,
    g: u8,
    b: u8,
    const Self = @This();
    const white = Self{ .r = 255, .g = 255, .b = 255 };
    const black = Self{ .r = 0, .g = 0, .b = 0 };
};

const BGRPixelWriter = struct {
    config_: *FrameBufferConfig,

    const Self = @This();
    fn new(config: *FrameBufferConfig) Self {
        return Self{ .config_ = config };
    }
    fn pixel_at(self: *Self, x: usize, y: usize) [*]u8 {
        var frame_buffer = @ptrCast([*]u8, self.config_.frame_buffer);
        return frame_buffer + 4 * (self.config_.pixels_per_scan_line * y + x);
    }
    fn write(self: *Self, x: usize, y: usize, col: *const PixelColor) void {
        var p = self.pixel_at(x, y);
        p[0] = col.b;
        p[1] = col.g;
        p[2] = col.r;
    }

    fn getFont(c: u8) ?[*]u8 {
        var index: usize = 16 * @intCast(usize, c);
        if (index >= @ptrToInt(&_binary_hankaku_bin_size)) {
            return null;
        }
        return @ptrCast([*]u8, &_binary_hankaku_bin_start) + index;
    }

    fn writeAscii(self: *Self, x: usize, y: usize, c: u8, col: *const PixelColor) void {
        const font = Self.getFont(c);
        if (font == null) {
            return;
        }
        comptime var dy: u8 = 0;
        inline while (dy < 16) : (dy += 1) {
            comptime var dx: u8 = 0;
            inline while (dx < 8) : (dx += 1) {
                if ((font.?[dy] << dx) & 0x80 != 0) {
                    self.write(x + dx, y + dy, col);
                }
            }
        }
    }
};

fn halt() void {
    while (true) {
        asm volatile ("hlt");
    }
}

