const std = @import("std");
pub fn main() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("Hello world\n", .{}) catch unreachable;
}
