const std = @import("std");
const uefi = std.os.uefi;
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const LR = std.unicode.utf8ToUtf16LeWithNull;
const fmt = std.fmt;

var memory_map: [4096 * 4]u8 = undefined;

var boot_services: *uefi.tables.BootServices = undefined;
var con_out: *uefi.protocols.SimpleTextOutputProtocol = undefined;
var sfsp: ?*uefi.protocols.SimpleFileSystemProtocol = undefined;
var gop: ?*uefi.protocols.GraphicsOutputProtocol = undefined;

var root_dir: *uefi.protocols.FileProtocol = undefined;

pub fn main() void {
    var buf: [100]u8 = undefined;
    var str_buf: [256]u8 = undefined;
    var bfa = std.heap.FixedBufferAllocator.init(str_buf[0..]);
    const allocator = bfa.allocator();

    init();

    var kernel_file: *uefi.protocols.FileProtocol = undefined;
    if (root_dir.open(&kernel_file, L("kernel.elf"), uefi.protocols.FileProtocol.efi_file_mode_read, 0) != uefi.Status.Success) {
        _ = con_out.outputString(L("failed to open kernel file\r\n"));
        halt();
    }

    const tmp_file_info_size = @sizeOf(uefi.protocols.FileInfo) + @sizeOf(u8) * 24;

    var file_info_size: u64 = tmp_file_info_size;
    var file_info_buffer: [tmp_file_info_size]u8 = undefined;

    if (kernel_file.getInfo(&uefi.protocols.FileInfo.guid, &file_info_size, &file_info_buffer) != uefi.Status.Success) {
        _ = con_out.outputString(L("failed to read file info\r\n"));
        halt();
    }

    var file_info: [*]uefi.protocols.FileInfo = @ptrCast([*]uefi.protocols.FileInfo, @alignCast(8, &file_info_buffer));
    const kernel_file_size = file_info[0].size;
    _ = con_out.outputString(LR(allocator, fmt.bufPrint(buf[0..], "kenrel_file_size = {d}\r\n", .{kernel_file_size}) catch unreachable) catch unreachable);

    halt();
}

fn init() void {
    boot_services = uefi.system_table.boot_services.?;
    con_out = uefi.system_table.con_out.?;
    _ = con_out.reset(false);

    _ = con_out.outputString(L("boot init start\r\n"));

    if (boot_services.locateProtocol(&uefi.protocols.SimpleFileSystemProtocol.guid, null, @ptrCast(*?*anyopaque, &sfsp)) != uefi.Status.Success) {
        _ = con_out.outputString(L("cannot locate simple file system protocol\r\n"));
        halt();
    }

    if (sfsp.?.openVolume(&root_dir) != uefi.Status.Success) {
        _ = con_out.outputString(L("cannot open volume\r\n"));
        halt();
    }

    if (boot_services.locateProtocol(&uefi.protocols.GraphicsOutputProtocol.guid, null, @ptrCast(*?*anyopaque, &gop)) != uefi.Status.Success) {
        _ = con_out.outputString(L("cannot locate graphics output protocol\r\n"));
        halt();
    }
    _ = con_out.outputString(L("boot init success!\r\n"));
}

fn halt() void {
    while (true) {
        asm volatile ("hlt");
    }
}
