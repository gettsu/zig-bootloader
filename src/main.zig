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

const FrameBufferConfig = extern struct {
    frame_buffer: [*]u8,
    pixels_per_scan_line: u32,
    horizontal_resolution: u32,
    vertical_resolution: u32,
    pixel_format: uefi.protocols.GraphicsPixelFormat,
};

// uefiとsystemV64ではabiが違うため一度変換
// integerはrcx -> rdx -> r8 -> r9 -> stack の順
comptime {
    asm (
        \\.global entryPoint
        \\entryPoint:
        \\    pushq %rbp
        \\    movq %rsp, %rbp
        \\    movq %rdx, %rdi
        \\    movq %r8, %rsi
        \\    callq *%rcx
        \\    movq %rbp, %rsp
        \\    popq %rbp
        \\    retq
    );
}

extern fn entryPoint(entry_addr: u64, frame_buffer_config: *FrameBufferConfig, acpi_table: *anyopaque) void;

pub fn main() void {
    var status: uefi.Status = undefined;
    // 文字列をUTF-16に変換するためのアロケーター
    var str_buf: [256]u8 = undefined;
    var bfa = std.heap.FixedBufferAllocator.init(str_buf[0..]);
    const allocator = bfa.allocator();

    // プロトコルの取得
    init(allocator);

    var acpi_table = findEfiAcpiTable().?;
    const s = @ptrCast([*]u8, acpi_table);
    printf(allocator, "{s}\r\n", .{s[0..7]});

    // カーネルファイルの取得
    var kernel_file: *uefi.protocols.FileProtocol = undefined;
    status = root_dir.open(&kernel_file, L("\\kernel.elf"), uefi.protocols.FileProtocol.efi_file_mode_read, 0);
    if (status != uefi.Status.Success) {
        printf(allocator, "failed to open kernel_file: {s}\r\n", .{@tagName(status)});
        halt();
    }

    // ファイル情報の取得
    var kernel_buffer: [*]align(8) u8 = undefined;
    readFile(allocator, kernel_file, &kernel_buffer);

    var kernel_first_addr: u64 = undefined;
    var kernel_last_addr: u64 = undefined;
    calcLoadAddressRange(kernel_buffer, &kernel_first_addr, &kernel_last_addr);

    const num_pages = (kernel_last_addr - kernel_first_addr + 0xfff) / 0x1000;
    status = boot_services.allocatePages(AllocateType.AllocateMaxAddress, MemoryType.LoaderData, num_pages, &(@alignCast(4096, (@intToPtr([*]u8, kernel_first_addr)))));
    if (status != uefi.Status.Success) {
        printf(allocator, "failed to allocate pages: {s}\r\n", .{@tagName(status)});
        halt();
    }

    copyLoadSegments(kernel_buffer);
    printf(allocator, "kernel: 0x{x} - 0x{x}\r\n", .{ kernel_first_addr, kernel_last_addr });

    status = boot_services.freePool(kernel_buffer);
    if (status != uefi.Status.Success) {
        printf(allocator, "failed to free pool: {s}\r\n", .{@tagName(status)});
        halt();
    }

    const entry_addr: u64 = @intToPtr(*u64, kernel_first_addr + 24).*;
    printf(allocator, "entry_addr = 0x{x}\r\n", .{entry_addr});

    var frame_buffer_config = FrameBufferConfig{
        .frame_buffer = @intToPtr([*]u8, gop.?.mode.frame_buffer_base),
        .vertical_resolution = gop.?.mode.info.vertical_resolution,
        .horizontal_resolution = gop.?.mode.info.horizontal_resolution,
        .pixels_per_scan_line = gop.?.mode.info.pixels_per_scan_line,
        .pixel_format = gop.?.mode.info.pixel_format,
    };
    // メモリマップ取得
    var mmap_size: usize = @sizeOf(@TypeOf(memory_map));
    var mmap_key: usize = undefined;
    var desc_size: usize = undefined;
    var desc_version: u32 = undefined;
    status = boot_services.getMemoryMap(&mmap_size, @ptrCast([*]MemoryDescriptor, &memory_map), &mmap_key, &desc_size, &desc_version);
    if (status != uefi.Status.Success) {
        printf(allocator, "failed to get memorymap: {s}\r\n", .{@tagName(status)});
        halt();
    }

    // exit boot service
    status = boot_services.exitBootServices(uefi.handle, mmap_key);
    if (status != uefi.Status.Success) {
        printf(allocator, "exitBootServices fail: {s}\r\n", .{@tagName(status)});
        halt();
    }

    entryPoint(entry_addr, &frame_buffer_config, acpi_table);
    halt();
}

fn init(allocator: std.mem.Allocator) void {
    var status: uefi.Status = undefined;
    boot_services = uefi.system_table.boot_services.?;
    con_out = uefi.system_table.con_out.?;
    _ = con_out.reset(false);

    printf(allocator, "boot init start\r\n", .{});

    status = boot_services.locateProtocol(&uefi.protocols.SimpleFileSystemProtocol.guid, null, @ptrCast(*?*anyopaque, &sfsp));
    if (status != uefi.Status.Success) {
        printf(allocator, "cannot locate simple file system protocol: {s}\r\n", .{@tagName(status)});
        halt();
    }

    status = sfsp.?.openVolume(&root_dir);
    if (status != uefi.Status.Success) {
        printf(allocator, "cannot open volume: {s}\r\n", .{@tagName(status)});
        halt();
    }

    status = boot_services.locateProtocol(&uefi.protocols.GraphicsOutputProtocol.guid, null, @ptrCast(*?*anyopaque, &gop));
    if (status != uefi.Status.Success) {
        printf(allocator, "cannot locate graphics output protocol: {s}\r\n", .{@tagName(status)});
        halt();
    }
    printf(allocator, "current graphic mode {} = {}x{}\r\n", .{ gop.?.mode.mode, gop.?.mode.info.horizontal_resolution, gop.?.mode.info.vertical_resolution });
    printf(allocator, "pixel_format = {s}\r\n", .{@tagName(gop.?.mode.info.pixel_format)});

    printf(allocator, "boot init success!\r\n", .{});
}

fn readFile(allocator: std.mem.Allocator, file: *uefi.protocols.FileProtocol, buffer: *[*]align(8) u8) void {
    var status: uefi.Status = undefined;
    const tmp_file_info_size = @sizeOf(uefi.protocols.FileInfo) + @sizeOf(u16) * 12;
    var file_info_size: u64 = tmp_file_info_size;
    var file_info_buffer: [tmp_file_info_size]u8 = undefined;
    status = file.getInfo(&uefi.protocols.FileInfo.guid, &file_info_size, &file_info_buffer);
    if (status != uefi.Status.Success) {
        printf(allocator, "failed to read file_info: {s}\r\n", .{@tagName(status)});
        halt();
    }

    const file_info: *uefi.protocols.FileInfo = @ptrCast(*uefi.protocols.FileInfo, @alignCast(8, &file_info_buffer));
    var file_size = file_info.file_size;
    {
        _ = con_out.outputString(L("file_name = "));
        _ = con_out.outputString(file_info.getFileName());
        _ = con_out.outputString(L("\r\n"));
    }

    status = boot_services.allocatePool(MemoryType.LoaderData, file_size, buffer);
    if (status != uefi.Status.Success) {
        printf(allocator, "failed to allocate file: {s}\r\n", .{@tagName(status)});
        halt();
    }

    status = file.read(&file_size, buffer.*);
    if (status != uefi.Status.Success) {
        printf(allocator, "failed to read file: {s}\r\n", .{@tagName(status)});
        halt();
    }
}

fn findEfiAcpiTable() ?*anyopaque {
    const acpi_guid = uefi.tables.ConfigurationTable.acpi_20_table_guid;

    var i: usize = 0;
    while (i < uefi.system_table.number_of_table_entries) : (i += 1) {
        const vendor_guid = uefi.system_table.configuration_table[i].vendor_guid;
        if (acpi_guid.eql(vendor_guid)) {
            return uefi.system_table.configuration_table[i].vendor_table;
        }
    }
    return null;
}

fn calcLoadAddressRange(kernel_buffer: [*]u8, first: *u64, last: *u64) void {
    const ehdr: *elf.Elf64_Ehdr = @ptrCast(*elf.Elf64_Ehdr, @alignCast(8, kernel_buffer));
    var phdr: [*]elf.Elf64_Phdr = @intToPtr([*]elf.Elf64_Phdr, @ptrToInt(kernel_buffer) + ehdr.e_phoff);
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

fn copyLoadSegments(kernel_buffer: [*]u8) void {
    const ehdr: *elf.Elf64_Ehdr = @ptrCast(*elf.Elf64_Ehdr, @alignCast(8, kernel_buffer));
    var phdr: [*]elf.Elf64_Phdr = @intToPtr([*]elf.Elf64_Phdr, @ptrToInt(kernel_buffer) + ehdr.e_phoff);

    var i: usize = 0;
    while (i < ehdr.e_phnum) : (i += 1) {
        if (phdr[i].p_type != elf.PT_LOAD) {
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
