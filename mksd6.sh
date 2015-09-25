#!/bin/bash

LOOP_DEV=loop0
IMG_SIZE=6442450944  #6GB
KERNEL_VER=4.1.5

dd if=/dev/zero of=rpi.img count=0 bs=1 seek=$IMG_SIZE

sudo sh -c 'cat << EOF | sfdisk --force rpi.img
unit: sectors
1 : start=     2048, size=   4192256, Id= c
2 : start=  4194304, size=   8388608, Id=83
EOF
'
sudo losetup /dev/$LOOP_DEV rpi.img -o $((2048*512))
sudo mkfs.vfat -F 32 -n firmware /dev/$LOOP_DEV
sleep 1
sudo losetup -d /dev/$LOOP_DEV
sudo losetup /dev/$LOOP_DEV rpi.img -o $((4194304*512))
sudo mkfs.ext4 -L root /dev/$LOOP_DEV
sleep 1
sudo losetup -d /dev/$LOOP_DEV

mkdir -p mnt/{firmware,root}
sudo mount -o loop,offset=$((2048*512)) rpi.img mnt/firmware
sudo mount -o loop,offset=$((4194304*512)) rpi.img mnt/root

sudo rsync -a rootfs/ mnt/root/
#sudo cp -a rootfs/boot/* mnt/firmware/
sudo cp -a ../firmware/hardfp/opt/vc mnt/root/opt/
sudo cp -a ../linux/build/dist/lib/modules mnt/root/lib/
sudo cp -a ../linux/build/dist/include/* mnt/root/usr/include
sudo cp ../linux/build/.config mnt/root/boot/config-${KERNEL_VER}-preempt-rt5
sudo cp ../linux/build/arch/arm/boot/zImage mnt/firmware/kernel.img
sudo cp ../firmware/boot/{*bin,*dat,*elf} mnt/firmware/
sudo sh -c 'cat > mnt/firmware/config.txt << EOF
kernel=kernel.img
core_freq=250
sdram_freq=400
over_voltage=0
gpu_mem=16
EOF
'
sudo sh -c 'cat > mnt/firmware/cmdline.txt << EOF
dwc_otg.fiq_enable=0 dwc_otg.fiq_fsm_enable=0 dwc_otg.nak_holdoff=0 dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait
EOF
'
sudo umount mnt/{firmware,root}

bzip2 -9 rpi.img

# sudo sh -c 'bzcat rpi.img.bz2 > /dev/mmcblk0'
