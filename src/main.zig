const std = @import("std");
const uefi = std.os.uefi;
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const LA = std.unicode.utf8ToUtf16LeWithNull;
const fmt = std.fmt;
const MemoryDescriptor = uefi.tables.MemoryDescriptor;

const MemoryType = uefi.tables.MemoryType;
const AllocateType = uefi.tables.AllocateType;

var memory_map: [4096 * 4]u8 = undefined;

var boot_services: *uefi.tables.BootServices = undefined;
var con_out: *uefi.protocols.SimpleTextOutputProtocol = undefined;
var sfsp: ?*uefi.protocols.SimpleFileSystemProtocol = undefined;
var gop: ?*uefi.protocols.GraphicsOutputProtocol = undefined;

var root_dir: *uefi.protocols.FileProtocol = undefined;

// uefiとsystemV64ではabiが違うため一度変換
// integerはrcx -> rdx -> r8 -> r9 -> stack の順
comptime {
    asm (
        \\.global entryPoint
        \\entryPoint:
        \\    push %rbp
        \\    mov %rsp, %rbp
        \\    call *%rcx
        \\    mov %rbp, %rsp
        \\    pop %rbp
        \\    retq
        \\    ud2
    );
}

extern fn entryPoint(entry_addr: u64) void;

pub fn main() void {
    // 文字列をUTF-16に変換するためのアロケーター
    var str_buf: [256]u8 = undefined;
    var bfa = std.heap.FixedBufferAllocator.init(str_buf[0..]);
    const allocator = bfa.allocator();

    // プロトコルの取得
    init(allocator);

    // カーネルファイルの取得
    var kernel_file: *uefi.protocols.FileProtocol = undefined;
    if (root_dir.open(&kernel_file, L("\\kernel.elf"), uefi.protocols.FileProtocol.efi_file_mode_read, 0) != uefi.Status.Success) {
        printf(allocator, "failed to open kernel_file\r\n", .{});
        halt();
    }

    // ファイル情報の取得
    const tmp_file_info_size = @sizeOf(uefi.protocols.FileInfo) + @sizeOf(u16) * 12;
    var file_info_size: u64 = tmp_file_info_size;
    var file_info_buffer: [tmp_file_info_size]u8 = undefined;
    if (kernel_file.getInfo(&uefi.protocols.FileInfo.guid, &file_info_size, &file_info_buffer) != uefi.Status.Success) {
        printf(allocator, "failed to read file_info\r\n", .{});
        halt();
    }
    var file_info: *uefi.protocols.FileInfo = @ptrCast(*uefi.protocols.FileInfo, @alignCast(8, &file_info_buffer));
    {
        _ = con_out.outputString(L("file_name = "));
        _ = con_out.outputString(file_info.getFileName());
        _ = con_out.outputString(L("\r\n"));
    }

    var kernel_file_size = file_info.file_size;
    printf(allocator, "kernel_file_size = {}\r\n", .{kernel_file_size});

    // ファイルをkernel_base_addrに読み出す処理
    var kernel_base_addr: u64 = 0x100000;
    if (boot_services.allocatePages(AllocateType.AllocateAddress, MemoryType.LoaderData, (kernel_file_size + 0xfff) / 0x1000, &(@alignCast(4096, (@intToPtr([*]u8, kernel_base_addr))))) != uefi.Status.Success) {
        printf(allocator, "allocation for kernel.elf failed\r\n", .{});
        halt();
    }
    if (kernel_file.read(&kernel_file_size, @intToPtr([*]u8, kernel_base_addr)) != uefi.Status.Success) {
        printf(allocator, "cannot read kernel_file\r\n", .{});
        halt();
    }

    const entry_addr: u64 = @intToPtr(*u64, kernel_base_addr + 24).*;
    printf(allocator, "entry_addr = 0x{x}\r\n", .{entry_addr});

    // メモリマップ取得
    var mmap_size: usize = @sizeOf(@TypeOf(memory_map));
    var mmap_key: usize = undefined;
    var desc_size: usize = undefined;
    var desc_version: u32 = undefined;
    if (boot_services.getMemoryMap(&mmap_size, @ptrCast([*]MemoryDescriptor, &memory_map), &mmap_key, &desc_size, &desc_version) != uefi.Status.Success) {
        printf(allocator, "Buffer Too Small\r\n", .{});
        halt();
    }

    // exit boot service
    if (boot_services.exitBootServices(uefi.handle, mmap_key) != uefi.Status.Success) {
        printf(allocator, "exitBootServices fail\r\n", .{});
        halt();
    }

    entryPoint(entry_addr);

    halt();
}

fn init(allocator: std.mem.Allocator) void {
    boot_services = uefi.system_table.boot_services.?;
    con_out = uefi.system_table.con_out.?;
    _ = con_out.reset(false);

    printf(allocator, "boot init start\r\n", .{});

    if (boot_services.locateProtocol(&uefi.protocols.SimpleFileSystemProtocol.guid, null, @ptrCast(*?*anyopaque, &sfsp)) != uefi.Status.Success) {
        printf(allocator, "cannot locate simple file system protocol\r\n", .{});
        halt();
    }

    if (sfsp.?.openVolume(&root_dir) != uefi.Status.Success) {
        printf(allocator, "cannot open volume\r\n", .{});
        halt();
    }

    if (boot_services.locateProtocol(&uefi.protocols.GraphicsOutputProtocol.guid, null, @ptrCast(*?*anyopaque, &gop)) != uefi.Status.Success) {
        printf(allocator, "cannot locate graphics output protocol\r\n", .{});
        halt();
    }
    printf(allocator, "current graphic mode {} = {}x{}\r\n", .{ gop.?.mode.mode, gop.?.mode.info.horizontal_resolution, gop.?.mode.info.vertical_resolution });

    printf(allocator, "boot init success!\r\n", .{});
}

fn halt() void {
    while (true) {
        asm volatile ("hlt");
    }
}

fn printf(allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) void {
    var buf: [128]u8 = undefined;
    const str = LA(allocator, fmt.bufPrint(buf[0..], format, args) catch unreachable) catch unreachable;
    _ = con_out.outputString(str);
    allocator.free(str);
}
