qemu: OVMF_CODE.fd OVMF_VARS.fd EFI/BOOT/BOOTX64.EFI
	qemu-system-x86_64 \
		-drive if=pflash,format=raw,readonly=on,file=./OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=./OVMF_VARS.fd \
		-drive file=fat:rw:.,media=disk,format=raw \
		-monitor stdio

OVMF_VARS.fd:
	wget https://retrage.github.io/edk2-nightly/bin/RELEASEX64_OVMF_VARS.fd
	mv RELEASEX64_OVMF_VARS.fd OVMF_VARS.fd

OVMF_CODE.fd:
	wget https://retrage.github.io/edk2-nightly/bin/RELEASEX64_OVMF_CODE.fd
	mv RELEASEX64_OVMF_CODE.fd OVMF_CODE.fd

OVMF.fd:
	wget http://downloads.sourceforge.net/project/edk2/OVMF/OVMF-X64-r15214.zip
	unzip OVMF-X64-r15214.zip OVMF.fd
	rm OVMF-X64-r15214.zip

clean:
	rm -f OVMF.fd NvVars OVMF_CODE.fd OVMF_VARS.fd
	rm -rf EFI
