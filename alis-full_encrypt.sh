#!/bin/bash - 
#===============================================================================
#
#          FILE: alis.sh
# 
#         USAGE: ./alis.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: YOUR NAME (), 
#  ORGANIZATION: 
#       CREATED: 31/05/19 14:30
#      REVISION:  ---
#===============================================================================

set -o nounset                              # Treat unset variables as an error
DEVICE="/dev/sda"
FILE_SYSTEM_TYPE="ext4"
LVM_VOLUME_PHISICAL="lvm"
LVM_VOLUME_GROUP="vg0"
LVM_VOLUME_SWAP="swap"
LVM_VOLUME_ROOT="root"
LVM_VOLUME_HOME="home"
SWAP_SIZE="1G"
ROOT_SIZE="4G"
BOOT_DIRECTORY=""
ESP_DIRECTORY=""
UUID_BOOT=""
UUID_ROOT=""
PARTUUID_BOOT=""
PARTUUID_ROOT=""

source alis.conf

function check_variables() {
check_variables_equals "PARTITION_ROOT_ENCRYPTION_PASSWORD" "PARTITION_ROOT_ENCRYPTION_PASSWORD_RETYPE" "$PARTITION_ROOT_ENCRYPTION_PASSWORD" "$PARTITION_ROOT_ENCRYPTION_PASSWORD_RETYPE"
check_variables_equals "PARTITION_BOOT_ENCRYPTION_PASSWORD" "PARTITION_BOOT_ENCRYPTION_PASSWORD_RETYPE" "$PARTITION_BOOT_ENCRYPTION_PASSWORD" "$PARTITION_BOOT_ENCRYPTION_PASSWORD_RETYPE"
    check_variables_value "TIMEZONE" "$TIMEZONE"
    check_variables_value "LOCALE" "$LOCALE"
    check_variables_value "LANG" "$LANG"
    check_variables_value "KEYMAP" "$KEYMAP"
    check_variables_value "HOSTNAME" "$HOSTNAME"
    check_variables_value "USER_NAME" "$USER_NAME"
    check_variables_value "USER_PASSWORD" "$USER_PASSWORD"
    check_variables_equals "ROOT_PASSWORD" "ROOT_PASSWORD_RETYPE" "$ROOT_PASSWORD" "$ROOT_PASSWORD_RETYPE"
    check_variables_equals "USER_PASSWORD" "USER_PASSWORD_RETYPE" "$USER_PASSWORD" "$USER_PASSWORD_RETYPE"
}

function check_variables_value() {
    NAME=$1
    VALUE=$2
    if [ -z "$VALUE" ]; then
        echo "$NAME environment variable must have a value."
        exit
    fi
}

function check_variables_equals() {
    NAME1=$1
    NAME2=$2
    VALUE1=$3
    VALUE2=$4
    if [ "$VALUE1" != "$VALUE2" ]; then
        echo "$NAME1 and $NAME2 must be equal [$VALUE1, $VALUE2]."
        exit
    fi
}


BIOS_TYPE="uefi"
DEVICE_SATA="true"

timedatectl set-ntp true

function partition() {
        echo "Creating partitions..."
        PARTITION_EFI="${DEVICE}2"
        PARTITION_BOOT="${DEVICE}3"
        PARTITION_ROOT="${DEVICE}4"
        #DEVICE_ROOT="${DEVICE}2"
        
        sgdisk -o "$DEVICE"
        sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS Boot Partition" "$DEVICE"
        sgdisk -n 2:0:+550M -t 2:ef00 -c 2:"EFI System Partition" "$DEVICE"
        sgdisk -n 3:0:+200M -t 3:8300 -c 3:"Boot partition" "$DEVICE"
        sgdisk -n 4:0:0 -t 4:8e00 -c 4:"LVM partition" "$DEVICE"
        sgdisk -p "$DEVICE"

        echo -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" | cryptsetup -v --cipher \
                serpent-xts-plain64 --key-size 512 --key-file=- --hash whirlpool \
                --iter-time 500 --use-random  luksFormat --type luks2 $PARTITION_ROOT
        echo -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" | cryptsetup --key-file=- \
                open $PARTITION_ROOT $LVM_VOLUME_PHISICAL
        sleep 5
        
        pvcreate /dev/mapper/$LVM_VOLUME_PHISICAL
        vgcreate $LVM_VOLUME_GROUP /dev/mapper/$LVM_VOLUME_PHISICAL
        lvcreate -L $SWAP_SIZE $LVM_VOLUME_GROUP -n $LVM_VOLUME_SWAP
        lvcreate -L $ROOT_SIZE $LVM_VOLUME_GROUP -n $LVM_VOLUME_ROOT
        lvcreate -l 100%FREE $LVM_VOLUME_GROUP -n $LVM_VOLUME_HOME
        
        DEVICE_ROOT="/dev/mapper/$LVM_VOLUME_GROUP-$LVM_VOLUME_ROOT"
        DEVICE_HOME="/dev/mapper/$LVM_VOLUME_GROUP-$LVM_VOLUME_HOME"
        DEVICE_SWAP="/dev/mapper/$LVM_VOLUME_GROUP-$LVM_VOLUME_SWAP"
        DEVICE_BOOT="dev/mapper/cryptboot"

        echo -n "$PARTITION_BOOT_ENCRYPTION_PASSWORD" | cryptsetup -v luksFormat $PARITION_BOOT
        echo -n "$PARTITION_BOOT_ENCRYPTION_PASSWORD" | cryptsetup open $PARTITION_BOOT cryptboot
        
        echo "Format partitions..."
        mkfs.fat -F32 $PARTITION_EFI
        mkfs.ext4 /dev/mapper/cryptboot
        mkfs."$FILE_SYSTEM_TYPE" -L root $DEVICE_ROOT
        mkfs."$FILE_SYSTEM_TYPE" -L home $DEVICE_HOME
        mkswap $DEVICE_SWAP
        swapon $DEVICE_SWAP

        echo "Mount partitions..."
        PARTITION_OPTIONS="defaults,noatime"
        
        mount -o "$PARTITION_OPTIONS" "$DEVICE_ROOT" /mnt
        mkdir /mnt/{home,boot,efi}
        mount "$DEVICE_HOME" /mnt/home
        mount /dev/mapper/cryptboot /mnt/boot
        mount $PARTITION_EFI /mnt/efi

        BOOT_DIRECTORY=/boot
        ESP_DIRECTORY=/efi
        UUID_BOOT=$(blkid -s UUID -o value $PARTITION_BOOT)
        UUID_ROOT=$(blkid -s UUID -o value $PARTITION_ROOT)
        PARTUUID_BOOT=$(blkid -s PARTUUID -o value $PARTITION_BOOT)
        PARTUUID_ROOT=$(blkid -s PARTUUID -o value $PARTITION_ROOT)
}

function install () {
        pacstrap /mnt base base-devel
}

function configuration (){
        #echo "Encrypt home..."
        #mkdir -m 700 /mnt/etc/luks-keys
        #dd if=/dev/random of=/mnt/etc/luks-keys/home bs=1 count=256 status=progress
        #cryptsetup luksFormat -v /dev/$LVM_VOLUME_GROUP/home /mnt/etc/luks-keys/home
        #cryptsetup -d /mnt/etc/luks-keys/home open /dev/$LVM_VOLUME_GROUP/home home
        #mkfs."$FILE_SYSTEM_TYPE" /dev/mapper/home
        #mount /dev/mapper/home /mnt/home
        #echo "home /dev/$LVM_VOLUME_GROUP/home   /etc/luks-keys/home" >> /mnt/etc/crypttab
        
        echo "Generating fstab..."
        genfstab -U /mnt >> /mnt/etc/fstab

        echo "Set configs..."
        arch-chroot /mnt ln -s -f $TIMEZONE /etc/localtime
        arch-chroot /mnt hwclock --systohc
        sed -i "s/#$LOCALE/$LOCALE/" /mnt/etc/locale.gen
        arch-chroot /mnt locale-gen
        echo -e "$LANG\n$LANGUAGE" > /mnt/etc/locale.conf
        echo -e "$KEYMAP\n$FONT\n$FONT_MAP" > /mnt/etc/vconsole.conf
        echo $HOSTNAME > /mnt/etc/hostname
        printf "$ROOT_PASSWORD\n$ROOT_PASSWORD" | arch-chroot /mnt passwd
}

function mkinitcpio(){
        MODULES="amdgpu"
        arch-chroot /mnt sed -i "s/MODULES=()/MODULES=($MODULES)/" /etc/mkinitcpio.conf
        arch-chroot /mnt sed -i 's/ block / block keyboard keymap /' /etc/mkinitcpio.conf
        arch-chroot /mnt sed -i 's/ filesystems keyboard / encrypt lvm2 filesystems /' /etc/mkinitcpio.conf
        arch-chroot /mnt mkinitcpio -P
}

function bootloader(){
        echo "Setting Bootloader..."
        BOOTLOADER_ALLOW_DISCARDS=":allow-discards"
        CMDLINE_LINUX="cryptdevice=PARTUUID=$PARTUUID_ROOT:$LVM_VOLUME_PHISICAL$BOOTLOADER_ALLOW_DISCARDS"
        pacman_install "grub dosfstools"
        arch-chroot /mnt sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /etc/default/grub
        arch-chroot /mnt sed -i 's/#GRUB_SAVEDEFAULT="true"/GRUB_SAVEDEFAULT="true"/' /etc/default/grub
        arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
        arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="'$CMDLINE_LINUX'"/' /etc/default/grub
        echo "" >> /mnt/etc/default/grub
        echo "GRUB_DISABLE_SUBMENU=y" >> /mnt/etc/default/grub
        pacman_install "efibootmgr"
        
        echo "Installing bootloader..."
        mkdir /boot/grub
        grub-mkconfig -o /boot/grub/grub.cfg
        
        arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory=$ESP_DIRECTORY --recheck
        grub-install --target=i386-pc --recheck "$DRIVE"
        #arch-chroot /mnt grub-mkconfig -o "$BOOT_DIRECTORY/grub/grub.cfg"
}

function users() {
        echo "creating user $USER_NAME..."
        create_user $USER_NAME $USER_PASSWORD
        arch-chroot /mnt sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
}

function create_user() {
        USER_NAME=$1
        USER_PASSWORD=$2
        arch-chroot /mnt useradd -m -G wheel,storage,optical -s /bin/bash $USER_NAME
        printf "$USER_PASSWORD\n$USER_PASSWORD" | arch-chroot /mnt passwd $USER_NAME
}


function pacman_install() {
        PACKAGES=$1
        for VARIABLE in {1..5}
        do
                arch-chroot /mnt pacman -Syu --noconfirm $PACKAGES
                if [ $? == 0 ]; then
                        break
                else
                        sleep 10
                fi
        done
}

function main (){
        check_variables
        partition
        install
        configuration
        mkinitcpio
        bootloader
        users
}

main
