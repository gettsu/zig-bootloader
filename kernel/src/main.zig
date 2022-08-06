const std = @import("std");
const uefi = std.os.uefi;

const FrameBufferConfig = extern struct {
    frame_buffer: [*]u8,
    pixels_per_scan_line: u32,
    horizontal_resolution: u32,
    vertical_resolution: u32,
    pixel_format: uefi.protocols.GraphicsPixelFormat,
};

export fn kernelMain(frame_buffer_config: *FrameBufferConfig) void {
    var i: usize = 0;
    while (i < frame_buffer_config.horizontal_resolution * frame_buffer_config.vertical_resolution * 4): (i += 1) {
        if (i % 4 == 0) {
            frame_buffer_config.frame_buffer[i] = @intCast(u8, i % 256);
        }
    }
    while (true) {
        asm volatile ("hlt");
    }
}
