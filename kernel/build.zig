const std = @import("std");
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("kernel.elf", "src/main.zig");
    exe.setTarget(CrossTarget{ .cpu_arch = Target.Cpu.Arch.x86_64, .os_tag = Target.Os.Tag.freestanding, .abi = Target.Abi.gnu });
    exe.setOutputDir("..");
    exe.setBuildMode(mode);
    exe.install();
}
