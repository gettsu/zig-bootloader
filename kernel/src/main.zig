const std = @import("std");
const uefi = std.os.uefi;
const GraphicsPixelFormat = uefi.protocols.GraphicsPixelFormat;

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
    fn write(self: *Self, x: usize, y: usize, col: PixelColor) void {
        var p = self.pixel_at(x, y);
        p[0] = col.b;
        p[1] = col.g;
        p[2] = col.r;
    }
};

export fn kernelMain(frame_buffer_config: *FrameBufferConfig) void {
    var pixel_writer = BGRPixelWriter.new(frame_buffer_config);

    var i: usize = 0;
    while (i < frame_buffer_config.horizontal_resolution * frame_buffer_config.vertical_resolution) : (i += 1) {
        pixel_writer.write(i % frame_buffer_config.horizontal_resolution, i / frame_buffer_config.horizontal_resolution, PixelColor{ .r = 0, .g = 255, .b = 255 });
    }
    halt();
}
fn halt() void {
    while (true) {
        asm volatile ("hlt");
    }
}
