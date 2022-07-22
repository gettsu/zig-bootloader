const std = @import("std");
const uefi = std.os.uefi;
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const LA = std.unicode.utf8ToUtf16LeWithNull;
const fmt = std.fmt;
const elf = std.elf;
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
    var kernel_buffer: [*]align(8)u8 = undefined;
    readFile(allocator, kernel_file, &kernel_buffer);

    var kernel_first_addr: u64 = undefined;
    var kernel_last_addr: u64 = undefined;
    calcLoadAddressRange(kernel_buffer, &kernel_first_addr, &kernel_last_addr);

    const num_pages = (kernel_last_addr - kernel_first_addr + 0xfff) / 0x1000;
    if (boot_services.allocatePages(AllocateType.AllocateMaxAddress, MemoryType.LoaderData, num_pages, &(@alignCast(4096, (@intToPtr([*]u8, kernel_first_addr)))))!= uefi.Status.Success) {
        printf(allocator, "failed to allocate pages\r\n", .{});
        halt();
    }

    copyLoadSegments(kernel_buffer);
    printf(allocator, "kernel: 0x{x} - 0x{x}\r\n", .{kernel_first_addr, kernel_last_addr});

    if (boot_services.freePool(kernel_buffer) != uefi.Status.Success) {
        printf(allocator, "failed to free pool\r\n", .{});
        halt();
    }

    const entry_addr: u64 = @intToPtr(*u64, kernel_first_addr + 24).*;
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

fn readFile(allocator: std.mem.Allocator, file: *uefi.protocols.FileProtocol, buffer: *[*]align(8) u8) void {
    const tmp_file_info_size = @sizeOf(uefi.protocols.FileInfo) + @sizeOf(u16) * 12;
    var file_info_size: u64 = tmp_file_info_size;
    var file_info_buffer: [tmp_file_info_size]u8 = undefined;
    if (file.getInfo(&uefi.protocols.FileInfo.guid, &file_info_size, &file_info_buffer) != uefi.Status.Success) {
        printf(allocator, "failed to read file_info\r\n", .{});
        halt();
    }

    const file_info: *uefi.protocols.FileInfo = @ptrCast(*uefi.protocols.FileInfo, @alignCast(8, &file_info_buffer));
    var file_size = file_info.file_size;
    {
        _ = con_out.outputString(L("file_name = "));
        _ = con_out.outputString(file_info.getFileName());
        _ = con_out.outputString(L("\r\n"));
    }

    if (boot_services.allocatePool(MemoryType.LoaderData, file_size, buffer) != uefi.Status.Success) {
        printf(allocator, "failed to allocate file\r\n", .{});
        halt();
    }

    if (file.read(&file_size, buffer.*) != uefi.Status.Success) {
        printf(allocator, "failed to read file\r\n", .{});
        halt();
    }
}

fn calcLoadAddressRange(kernel_buffer: [*]u8, first: *u64, last: *u64) void {
    const ehdr :*elf.Elf64_Ehdr = @ptrCast(*elf.Elf64_Ehdr, @alignCast(8, kernel_buffer));
    var phdr: [*]elf.Elf64_Phdr = @intToPtr([*]elf.Elf64_Phdr,@ptrToInt(kernel_buffer) + ehdr.e_phoff);
    var i: usize = 0;
    first.* = std.math.inf_u64;
    last.* = 0;
    while (i < ehdr.e_phnum) : (i += 1) {
        if (phdr[i].p_type != elf.PT_LOAD) {
            continue;
        }
        first.* = std.math.min(first.*, phdr[i].p_vaddr);
        last.* = std.math.max(last.*, phdr[i].p_vaddr + phdr[i].p_memsz);
    }
}

fn copyLoadSegments(kernel_buffer: [*]u8)void {
    const ehdr :*elf.Elf64_Ehdr = @ptrCast(*elf.Elf64_Ehdr, @alignCast(8, kernel_buffer));
    var phdr: [*]elf.Elf64_Phdr = @intToPtr([*]elf.Elf64_Phdr,@ptrToInt(kernel_buffer) + ehdr.e_phoff);

    var i: usize = 0;
    while (i < ehdr.e_phnum) : (i += 1) {
        if (phdr[i].p_type != elf.PT_LOAD){
            continue;
        }
        var segm_in_file: usize = @ptrToInt(ehdr) + phdr[i].p_offset;
        @memcpy(@intToPtr([*]u8, phdr[i].p_vaddr), @intToPtr([*]u8, segm_in_file), phdr[i].p_filesz);
        var remain_bytes: usize = phdr[i].p_memsz - phdr[i].p_filesz;
        @memset(@intToPtr([*]u8, phdr[i].p_vaddr) + phdr[i].p_filesz, 0, remain_bytes);
    }
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
