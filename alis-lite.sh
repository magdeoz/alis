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
LVM_VOLUME_GROUP="vg"
LVM_VOLUME_ROOT="root"
LVM_VOLUME_HOME="home"
BOOT_DIRECTORY=""
ESP_DIRECTORY=""
#PARTITION_BOOT_NUMBER=0
UUID_BOOT=""
UUID_ROOT=""
PARTUUID_BOOT=""
PARTUUID_ROOT=""

 source alis.conf

function sanitize_variables() {
    DEVICE=$(sanitize_variable "$DEVICE")
    SWAP_SIZE=$(sanitize_variable "$SWAP_SIZE")
    ROOT_SIZE=$(sanitize_variable "$ROOT_SIZE")
}

function sanitize_variable() {
    VARIABLE=$1
    VARIABLE=$(echo $VARIABLE | sed "s/![^ ]*//g") # remove disabled
    VARIABLE=$(echo $VARIABLE | sed "s/ {2,}/ /g") # remove unnecessary white spaces
    VARIABLE=$(echo $VARIABLE | sed 's/^[[:space:]]*//') # trim leading
    VARIABLE=$(echo $VARIABLE | sed 's/[[:space:]]*$//') # trim trailing
    echo "$VARIABLE"
}

function check_variables() {
    check_variables_equals "PARTITION_ROOT_ENCRYPTION_PASSWORD" "PARTITION_ROOT_ENCRYPTION_PASSWORD_RETYPE" "$PARTITION_ROOT_ENCRYPTION_PASSWORD" "$PARTITION_ROOT_ENCRYPTION_PASSWORD_RETYPE"
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

function check_variables_boolean() {
    NAME=$1
    VALUE=$2
    check_variables_list "$NAME" "$VALUE" "true false"
}

function check_variables_list() {
    NAME=$1
    VALUE=$2
    VALUES=$3
    REQUIRED=$4
    if [ "$REQUIRED" == "" -o "$REQUIRED" == "true" ]; then
        check_variables_value "$NAME" "$VALUE"
    fi

    if [ "$VALUE" != "" -a -z "$(echo "$VALUES" | grep -F -w "$VALUE")" ]; then
        echo "$NAME environment variable value [$VALUE] must be in [$VALUES]."
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
    echo ""
    echo -e "${LIGHT_BLUE}# partition() step${NC}"
    echo ""

    sgdisk --zap-all $DEVICE
    wipefs -a $DEVICE
    PARTITION_BOOT="${DEVICE}1"
    PARTITION_ROOT="${DEVICE}2"
    DEVICE_ROOT="${DEVICE}2"
    parted -s $DEVICE mklabel gpt mkpart primary fat32 1MiB 512MiB mkpart primary $FILE_SYSTEM_TYPE 512MiB 100% set 1 boot on
    sgdisk -t=1:ef00 $DEVICE
    sgdisk -t=2:8e00 $DEVICE
    echo -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" | cryptsetup -v --cipher serpent-xts-plain64 --key-size 512 --key-file=- --hash whirlpool --iter-time 500 --use-random  luksFormat --type luks2 $PARTITION_ROOT
     echo -n "$PARTITION_ROOT_ENCRYPTION_PASSWORD" | cryptsetup --key-file=- open $PARTITION_ROOT $LVM_VOLUME_PHISICAL
     sleep 5
     pvcreate /dev/mapper/$LVM_VOLUME_PHISICAL
     vgcreate $LVM_VOLUME_GROUP /dev/mapper/$LVM_VOLUME_PHISICAL
     lvcreate -L $ROOT_SIZE $LVM_VOLUME_GROUP -n $LVM_VOLUME_ROOT
     lvcreate -l 100%FREE -n $LVM_VOLUME_HOME $LVM_VOLUME_GROUP
     DEVICE_ROOT="/dev/mapper/$LVM_VOLUME_GROUP-$LVM_VOLUME_ROOT"
     DEVICE_HOME="/dev/mapper/$LVM_VOLUME_GROUP-$LVM_VOLUME_HOME"
     wipefs -a $PARTITION_BOOT
     wipefs -a $DEVICE_ROOT
     mkfs.fat -n ESP -F32 $PARTITION_BOOT
     mkfs."$FILE_SYSTEM_TYPE" -L root $DEVICE_ROOT
     mkfs."$FILE_SYSTEM_TYPE" -L home $DEVICE_HOME

      PARTITION_OPTIONS="defaults,noatime"
      
      mount -o "$PARTITION_OPTIONS" "$DEVICE_ROOT" /mnt
      mkdir /mnt/home
      mkdir /mnt/boot
      mount -o "$PARTITION_OPTIONS" "$PARTITION_BOOT" /mnt/boot

      BOOT_DIRECTORY=/boot
      ESP_DIRECTORY=/boot
      UUID_BOOT=$(blkid -s UUID -o value $PARTITION_BOOT)
      UUID_ROOT=$(blkid -s UUID -o value $PARTITION_ROOT)
      PARTUUID_BOOT=$(blkid -s PARTUUID -o value $PARTITION_BOOT)
      PARTUUID_ROOT=$(blkid -s PARTUUID -o value $PARTITION_ROOT)
}

function install () {
     pacstrap /mnt base base-devel
}

function configuration (){

        genfstab -U /mnt >> /mnt/etc/fstab
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
        BOOTLOADER_ALLOW_DISCARDS=":allow-discards"
        CMDLINE_LINUX="cryptdevice=PARTUUID=$PARTUUID_ROOT:$LVM_VOLUME_PHISICAL$BOOTLOADER_ALLOW_DISCARDS"
        pacman_install "grub dosfstools"
        arch-chroot /mnt sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /etc/default/grub
        arch-chroot /mnt sed -i 's/#GRUB_SAVEDEFAULT="true"/GRUB_SAVEDEFAULT="true"/' /etc/default/grub
        arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
        arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="'$CMDLINE_LINUX'"/' /etc/default/grub
        echo "" >> /mnt/etc/default/grub
        echo "# alis" >> /mnt/etc/default/grub
        echo "GRUB_DISABLE_SUBMENU=y" >> /mnt/etc/default/grub

        pacman_install "efibootmgr"
        arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory=$ESP_DIRECTORY --recheck
        arch-chroot /mnt grub-mkconfig -o "$BOOT_DIRECTORY/grub/grub.cfg"
}

function users() {
    create_user $USER_NAME $USER_PASSWORD
    arch-chroot /mnt sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
}

function create_user() {
    echo ""
    echo -e "${LIGHT_BLUE}# create_user() step${NC}"
    echo ""

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
        configuration_install
        sanitize_variables
        check_variables
        partition
        install
        configuration
        mkinitcpio
        bootloader
        users
}

main
