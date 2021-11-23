#!/bin/bash

# 1. download image and unzip it
# 2. mount image
# 3. copy files from partitions to ./raspios_rootfs/ and ./raspios_rootfs/boot/
# 4. edit ./raspios_rootfs/etc/fstab, create template ./raspios_rootfs/boot/cmdline.txt.j2, enable ssh

image=2021-10-30-raspios-bullseye-armhf

sudo apt install unzip kpartx

# -nc, --no-clobber
wget -nc https://downloads.raspberrypi.org/raspios_armhf/images/raspios_armhf-2021-11-08/${image}.zip

sudo unzip -n ./$image.zip

mkdir -p ./{bootmnt,rootmnt} 

if command -v kpartx >> /dev/null
then
    sudo kpartx -a -v *.img && \
    sudo mount /dev/mapper/loop0p1 ./bootmnt/ && \
    sudo mount /dev/mapper/loop0p2 ./rootmnt/ || \
    exit 1

    umount_command="sudo umount bootmnt rootmnt; sudo kpartx -d ${image}.img"

else
        read -r boot_start boot_sectors root_start root_sectors \
         <<< `fdisk -l *.img | grep -A 2 Device | grep -v Device | tr -s ' ' | cut -f 2,4 -d ' ' | tr '\n' ' '`

    bytes=`fdisk -l *.img | grep Units | grep -Eo '[0-9]* bytes' |grep -Eo '[0-9]*'`

    let boot_offset=boot_start*bytes
    let boot_sizelimit=boot_sectors*bytes
    let root_offset=root_start*bytes
    let root_sizelimit=root_sectors*bytes

    sudo mount -o loop,offset=$boot_offset,sizelimit=$boot_sizelimit *.img ./bootmnt/
    sudo mount -o loop,offset=$root_offset,sizelimit=$root_sizelimit *.img ./rootmnt/

    umount_command="sudo umount bootmnt rootmnt"
fi


sudo mkdir -p ./raspios_rootfs
sudo cp -au ./rootmnt/* ./raspios_rootfs/
sudo cp -au ./bootmnt/* ./raspios_rootfs/boot/

eval $umount_command

sudo rm ./raspios_rootfs/boot/start4.elf
sudo rm ./raspios_rootfs/boot/fixup4.dat

sudo wget https://github.com/Hexxeh/rpi-firmware/raw/stable/start4.elf -P ./raspios_rootfs/boot/
sudo wget https://github.com/Hexxeh/rpi-firmware/raw/stable/fixup4.dat -P ./raspios_rootfs/boot/

sudo touch ./raspios_rootfs/boot/ssh

# comment strings containing UUID
sudo sed -i 's/\([^#]*.*UUID\)/#\1/g' ./raspios_rootfs/etc/fstab

# Jinja2 template for further configuration on the server
echo "console=serial0,115200 console=tty root=/dev/nfs nfsroot={{ NFS_IP }}:{{ NFS_PATH }},vers=3 rw ip=dhcp rootwait elevator=deadline usbhid.mousepoll=1" > ./raspios_rootfs/boot/cmdline.txt.j2
