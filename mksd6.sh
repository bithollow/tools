#!/bin/bash

LOOP_DEV=loop0
IMG_SIZE=6442450944  #6GB
KERNEL_VER=4.1.9
WIFI_DERIVER=8188eu-rpi-4.1.9-v7-preempt-rt8-4.1.7.tar.bz2
DEVICE_TREE_BLOB=bcm2709-rpi-2-b.dtb

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
sudo cp -a ../firmware/hardfp/opt/vc mnt/root/opt/
sudo cp -a ../linux/build/dist/lib/modules mnt/root/lib/
sudo cp -a ../linux/build/dist/include/* mnt/root/usr/include
sudo cp ../linux/build/.config mnt/root/boot/config-${KERNEL_VER}-preempt-rt8
#copy normal kernel, if use device tree, comment out line below
#sudo cp ../linux/build/arch/arm/boot/zImage mnt/firmware/kernel.img

#tailer kernel for device tree support and copy dtb & overlays to target folder
sudo ../tools/mkimage/mkknlimg --dtok ../linux/build/arch/arm/boot/zImage mnt/firmware/kernel.img
sudo cp ../linux/build/arch/arm/boot/dts/${DEVICE_TREE_BLOB} mnt/firmware/
sudo cp -a ../linux/build/arch/arm/boot/dts/overlays mnt/firmware/
sudo cp ../firmware/boot/{*bin,*dat,*elf} mnt/firmware/

#install tp-link 8188eu driver
if [ -e "../tools/pkg/${WIFI_DERIVER}" ]; then
    sudo cp ../tools/pkg/${WIFI_DERIVER} mnt/root/home/bit/
    sudo tar xvjf mnt/root/home/bit/${WIFI_DERIVER} -C mnt/root/home/bit/
    sudo chroot mnt/root /bin/bash -c "cd /home/bit/ ; ./install.sh"
else
    echo "Warning! You don't have wifi driver installed!"
fi

#strip rootfs
if [ "$1" = "-s" ]; then
    echo "strip rootfs..."
    sudo cp ../tools/clean_inside_chroot.sh mnt/root/home/bit/preinstall.sh
    sudo chroot mnt/root /bin/bash -c "cd /home/bit ; ./preinstall.sh"
    sudo rm -f mnt/root/home/bit/preinstall.sh
else
    echo "rootfs is not stripped"
fi

sudo sh -c 'cat > mnt/firmware/config.txt << EOF
#kernel=kernel.img
#core_freq=250
#sdram_freq=400
#over_voltage=0
#gpu_mem=16
dtparam=i2c_arm=on
dtparam=i2c_vc=on
dtparam=spi=on
EOF
'

sudo sh -c 'cat > mnt/firmware/cmdline.txt << EOF
dwc_otg.fiq_enable=0 dwc_otg.fiq_fsm_enable=0 dwc_otg.nak_holdoff=0 dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 root=/dev/mmcblk0p2 rw rootfstype=ext4 elevator=deadline rootwait
EOF
'

# TODO: should we add fsck.repair=yes to cmdline.txt?

if [ -e mnt/root/usr/bin/qemu-arm-static ]; then
    sudo rm -rf mnt/root/usr/bin/qemu-arm-static
fi

sudo umount mnt/{firmware,root}

sudo rm -f rpi.img.bz2
sync
bzip2 -9 rpi.img
sudo rm -rf mnt/firmware mnt/root

# sudo sh -c 'bzcat rpi.img.bz2 > /dev/mmcblk0'
