const std = @import("std");
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("kernel.elf", "src/main.zig");
    exe.setTarget(CrossTarget{ .cpu_arch = Target.Cpu.Arch.x86_64, .os_tag = Target.Os.Tag.freestanding, .abi = Target.Abi.gnu });
    exe.setOutputDir("..");
    exe.image_base = 0x100000;
    exe.red_zone = false;
    exe.entry_symbol_name = "kernelMain";
    exe.setBuildMode(mode);
    exe.install();
}
