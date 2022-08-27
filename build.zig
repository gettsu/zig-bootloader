const std = @import("std");
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;

pub fn build(b: *std.build.Builder) void {
    const exe = b.addExecutable("BOOTX64", "src/main.zig");
    const mode = b.standardReleaseOptions();
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setTarget(CrossTarget{
        .cpu_arch = Target.Cpu.Arch.x86_64,
        .os_tag = Target.Os.Tag.uefi,
        .abi = Target.Abi.msvc,
    });
    exe.setBuildMode(mode);
    exe.setOutputDir("EFI/BOOT");
    b.default_step.dependOn(&exe.step);
    exe.install();
}
