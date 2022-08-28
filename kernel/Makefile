hankaku.o: hankaku.bin
	objcopy -I binary -O elf64-x86-64 -B i386:x86-64 $< $@
hankaku.bin: hankaku.txt
	../tools/makefont.py -o $@ $<
.PHONY: clean
clean:
	rm -rf *.o *.bin
