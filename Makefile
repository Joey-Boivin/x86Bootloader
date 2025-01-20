ASM=nasm
BOOTLOADER_DIR=src/bootloader
KERNEL_DIR=src/kernel
BUILD_FOLDER=build
BIN_FOLDER=${BUILD_FOLDER}/bin

VERSION=0.0.0
IMG_NAME=SmolOS-${VERSION}.img

all: prep create_os_image

create_os_image: kernel bootloader 
	dd if=/dev/zero of=${BUILD_FOLDER}/${IMG_NAME} bs=512 count=2880
	mkfs.fat -F 12 -n "SMOLOS" ${BUILD_FOLDER}/${IMG_NAME}
	dd if=${BIN_FOLDER}/stage_one.bin of=${BUILD_FOLDER}/${IMG_NAME} conv=notrunc
	dd if=${BIN_FOLDER}/stage_two.bin of=${BUILD_FOLDER}/${IMG_NAME} seek=1 conv=notrunc
	mcopy -i ${BUILD_FOLDER}/${IMG_NAME} ${BIN_FOLDER}/kmain.bin "::kmain.bin"

bootloader: ${BOOTLOADER_DIR}/stage_one.s
	${ASM} ${BOOTLOADER_DIR}/stage_one.s -o ${BIN_FOLDER}/stage_one.bin
	${ASM} ${BOOTLOADER_DIR}/stage_two.s -o ${BIN_FOLDER}/stage_two.bin

kernel: ${KERNEL_DIR}/kmain.s
	${ASM} -i ${KERNEL_DIR} ${KERNEL_DIR}/kmain.s -o ${BIN_FOLDER}/kmain.bin

prep:
	mkdir -p ${BIN_FOLDER}

clean:
	rm -rf ${BUILD_FOLDER}
