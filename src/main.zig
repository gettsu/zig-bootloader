const std = @import("std");
const uefi = std.os.uefi;
const L = std.unicode.utf8ToUtf16LeStringLiteral;
// const LR = std.unicode.utf8ToUtf16LeWithNull;
// const fmt = std.fmt;

// var memory_map: [4096 * 4]u8 = undefined;

var boot_services: *uefi.tables.BootServices = undefined;
var con_out: *uefi.protocols.SimpleTextOutputProtocol = undefined;
var sfsp: ?*uefi.protocols.SimpleFileSystemProtocol = undefined;
var gop: ?*uefi.protocols.GraphicsOutputProtocol = undefined;


var root_dir: *uefi.protocols.FileProtocol = undefined;

pub fn main() void {
    init();
    while (true) {}
}

fn init() void {
    boot_services = uefi.system_table.boot_services.?;
    con_out = uefi.system_table.con_out.?;
    _ = con_out.reset(false);
    
    _ = con_out.outputString(L("boot init start\r\n"));

    if (boot_services.locateProtocol(&uefi.protocols.SimpleFileSystemProtocol.guid, null, @ptrCast(*?*anyopaque, &sfsp)) != uefi.Status.Success) {
        _ = con_out.outputString(L("cannot locate simple file system protocol\r\n"));
        while (true) {}
    }

    if (sfsp.?.openVolume(&root_dir) != uefi.Status.Success) {
        _ = con_out.outputString(L("cannot open volume\r\n"));
        while (true) {}
    }

    if (boot_services.locateProtocol(&uefi.protocols.GraphicsOutputProtocol.guid, null, @ptrCast(*?*anyopaque, &gop)) != uefi.Status.Success) {
        _ = con_out.outputString(L("cannot locate graphics output protocol\r\n"));
        while (true) {}
    }
    _ = con_out.outputString(L("boot init success!\r\n"));
}
