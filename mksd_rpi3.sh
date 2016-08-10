#!/bin/bash

LOOP_DEV=loop0
IMG_SIZE=6979321856  #6.5GB
KERNEL_VER=4.5.6
# aws WIFI_DERIVER=8188eu-rpi-4.1.9-v7-preempt-rt8-4.1.7.tar.bz2
DEVICE_TREE_BLOB=bcm2710-rpi-3-b.dtb

dd if=/dev/zero of=rpi.img count=0 bs=1 seek=$IMG_SIZE

#2GB for /firmware, 4GB for /
sudo sh -c 'cat << EOF | sfdisk --force rpi.img
unit: sectors
1 : start=     2048, size=   4194304, Id= c
2 : start=  4196352, size=   8388608, Id=83
EOF
'
sudo losetup /dev/$LOOP_DEV rpi.img -o $((2048*512)) --sizelimit $((4194304*512))
sudo mkfs.vfat -F 32 -n firmware /dev/$LOOP_DEV
sleep 1
sudo losetup -d /dev/$LOOP_DEV
sudo losetup /dev/$LOOP_DEV rpi.img -o $((4196352*512)) --sizelimit $((8388608*512))
sudo mkfs.ext4 -L root /dev/$LOOP_DEV
sleep 1
sudo losetup -d /dev/$LOOP_DEV

mkdir -p mnt/{firmware,root}
sudo mount -o loop,offset=$((2048*512)) rpi.img mnt/firmware
sudo mount -o loop,offset=$((4196352*512)) rpi.img mnt/root
sudo mkdir -p mnt/firmware/overlays

sudo rsync -a rootfs/ mnt/root/
sudo cp -a ../firmware/hardfp/opt/vc mnt/root/opt/
sudo cp -a ../linux/build/dist/lib/modules mnt/root/lib/
sudo cp -a ../linux/build/dist/include/* mnt/root/usr/include
sudo cp ../linux/build/.config mnt/root/boot/config-${KERNEL_VER}-preempt-rt9
#copy normal kernel, if use device tree, comment out line below
#sudo cp ../linux/build/arch/arm/boot/zImage mnt/firmware/kernel.img

#tailer kernel for device tree support and copy dtb & overlays to target folder
# aws sudo ../tools/mkimage/mkknlimg --dtok ../linux/build/arch/arm/boot/zImage mnt/firmware/kernel.img
sudo ../linux/scripts/mkknlimg --dtok ../linux/build/arch/arm/boot/zImage mnt/firmware/kernel.img
sudo cp ../linux/build/arch/arm/boot/dts/${DEVICE_TREE_BLOB} mnt/firmware/
sudo cp -a --no-preserve=ownership ../linux/build/arch/arm/boot/dts/overlays/*.dtbo mnt/firmware/overlays
sudo cp ../firmware/boot/{*bin,*dat,*elf} mnt/firmware/

#install tp-link 8188eu driver
# aws if [ -e "../tools/pkg/${WIFI_DERIVER}" ]; then
# aws   sudo cp ../tools/pkg/${WIFI_DERIVER} mnt/root/home/bit/
# aws   sudo tar xvjf mnt/root/home/bit/${WIFI_DERIVER} -C mnt/root/home/bit/
# aws   sudo chroot mnt/root /bin/bash -c "cd /home/bit/ ; ./install.sh"
# aws else
# aws   echo "Warning! You don't have wifi driver installed!"
# aws fi

#strip rootfs
# aws if [ "$1" = "-s" ]; then
# aws    echo "strip rootfs..."
# aws    sudo cp ../tools/clean_inside_chroot.sh mnt/root/home/bit/preinstall.sh
# aws    sudo chroot mnt/root /bin/bash -c "cd /home/bit ; ./preinstall.sh"
# aws    sudo rm -f mnt/root/home/bit/preinstall.sh
# aws else
# aws    echo "rootfs is not stripped"
# aws fi

sudo sh -c 'cat > mnt/firmware/config.txt << EOF
#kernel=kernel.img
#core_freq=250
#sdram_freq=400
#over_voltage=0
#gpu_mem=16
dtparam=i2c_arm=on
dtparam=i2c_vc=on
dtparam=spi=on
enable_uart=1
dtoverlay=pi3-miniuart-bt
dtoverlay=i2c-rtc,ds1339
EOF
'

sudo sh -c 'cat > mnt/firmware/cmdline.txt << EOF
dwc_otg.fiq_enable=0 dwc_otg.fiq_fsm_enable=0 dwc_otg.nak_holdoff=0 dwc_otg.lpm_enable=0 console=serial0,115200 kgdboc=serial0,115200 root=/dev/mmcblk0p2 rw rootfstype=ext4 elevator=deadline fsck.repair=yes root wait
EOF
'

if [ -e mnt/root/usr/bin/qemu-arm-static ]; then
    sudo rm -rf mnt/root/usr/bin/qemu-arm-static
fi

sudo umount mnt/{firmware,root}

sudo rm -f rpi.img.bz2
sync
bzip2 -9 rpi.img
sudo rm -rf mnt/firmware mnt/root

# sudo sh -c 'bzcat rpi.img.bz2 > /dev/mmcblk0'
