export fn kernelMain() void {
    while (true) {
        asm volatile ("hlt");
    }
}
