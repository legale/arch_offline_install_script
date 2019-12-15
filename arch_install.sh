#!/bin/bash

# functions
exiterr() { 
	echo "Error message: $1"	
	exit 1
}

function stage1(){
  log_progress "Installation stage 1..."
  make_partitions
  format_partitions
  mount_partitions
  find_the_fastest_mirror
  cp_system
}

function stage2(){
  log_progress "Installation stage 2..."
  is_chroot && echo "chroot ok" || exiterr "chroot check failed" 
  preconfig_system
  generate_fstab
  set_locale
  set_timezone_and_clock
  set_hostname
  make_initcpio
  echo -e "$PASS\n$PASS" | passwd root
  grub_install
}

make_partitions(){
  log_progress "making partitions..."
  local MNT=$(ls /dev/sda*)
  for i in $MNT; do
   umount $i -l
  done

  local string="parted -s "$DISK" \
  mklabel "$LABEL" \
  mkpart primary fat32 1 200 \
  set 1 boot on \
  mkpart primary ext2 200 100%"
  echo $string
  $string
}

function read_params(){
  STR=""
  if [ -z $1 ]; then
    read -p "Enter disk [/dev/sda]: " DISK
  fi
  DISK=${DISK:-/dev/sda}
  STR+=$DISK

  if [ -z $2 ]; then
    read -p "Enter partition type label (msdos/gpt) [msdos]: " LABEL
  fi
  LABEL=${LABEL:-msdos}
  STR+=" $LABEL"

  if [ -z $3 ]; then
    read -p "Enter country [Russia]: " COUNTRY
  fi
  COUNTRY=${COUNTRY:-Russia}
  STR+=" $COUNTRY"

  if [ -z $4 ]; then
    read -p "Enter city [Moscow]: " CITY
  fi
  CITY=${CITY:-Moscow}
  STR+=" $CITY"

  if [ -z $5 ]; then
    read -p "Enter hostname [archlinux]: " HOSTNAME
  fi
  HOSTNAME=${HOSTNAME:-archlinux}
  STR+=" $HOSTNAME"

  if [ -z $6 ]; then
    read -p "Enter root password [toor]: " PASS
  fi
  PASS=${PASS:-toor}
  STR+=" $PASS"

}

function format_partitions {
  log_progress "Formatting partitions..."
  mkfs.vfat -F32 ${DISK}1
  mkfs.ext4 -F ${DISK}2
}

function mount_partitions {
  log_progress "Mounting partitions..."
  mount ${DISK}2 /mnt
  mkdir -p /mnt/boot
  mount ${DISK}1 /mnt/boot
}

function find_the_fastest_mirror {
  log_progress "Find the fastest mirror..."
  pacman -Sy --noconfirm reflector
  eval $(echo "reflector --verbose --country '${COUNTRY}' -l 200 -p http --sort rate --save /etc/pacman.d/mirrorlist")
}

function generate_fstab {
  log_progress "Generating an fstab..."
  genfstab -U -p / > /etc/fstab
  cat /etc/fstab
}

function grub_install(){
  log_progress "Starting grub-install..."
  grub-install $DISK
  grub-mkconfig -o /boot/grub/grub.cfg
}

function chroot_install(){
  log_progress "Starting chroot..."
  cp $0 /mnt
  arch-chroot /mnt /bin/bash $0 $STR
  exit 0
}

function is_chroot(){
	log_progress "check if is_chroot..."
	if [ $(ls -di / | cut -d ' ' -f 1) == 2 ];then
	  return 0
	else
	  return 1
	fi 
}

function cp_system(){
  log_progress "copy system..."
  cp -ax / /mnt
  log_progress "copy kernel"
  cp -vaT /run/archiso/bootmnt/arch/boot/$(uname -m)/vmlinuz /mnt/boot/vmlinuz-linux
}

function preconfig_system(){
  log_progress "change journald config to store journal on disk..."
  sed -i 's/Storage=volatile/#Storage=auto/' /etc/systemd/journald.conf
  systemctl disable pacman-init.service choose-mirror.service
  rm -r /etc/systemd/system/{choose-mirror.service,\
   pacman-init.service,\
   etc-pacman.d-gnupg.mount,\
   getty@tty1.service.d}
  rm /etc/systemd/scripts/choose-mirror

  log_progress "remove autologin.conf, \
  /root/automated_script.sh,\
  /root/.zlogin, /etc/mkinitcpio-archiso.conf, /etc/initcpio"
  rm /etc/systemd/system/getty@tty1.service.d/autologin.conf
  rm /root/{.automated_script.sh,.zlogin}
  rm /etc/mkinitcpio-archiso.conf
  rm -r /etc/initcpio
  log_progress "import archlinux keys..."
  pacman-key --init
  pacman-key --populate archlinux
}

function set_locale {
  log_progress "Setting locale to UTF-8..."
  sed -i "s/#en_US\.UTF-8 UTF-8/en_US\.UTF-8 UTF-8/g" /etc/locale.gen
  locale-gen
  echo LANG=en_US.UTF-8 > /etc/locale.conf
  export LANG=en_US.UTF-8
}

function set_timezone_and_clock {
  log_progress "Setting timezone and clock..."
  ZONE=$(find /usr/share/zoneinfo -name $CITY | head -1)
  ZONE=${ZONE:-/usr/share/zoneinfo/UTC}
  ln -sf $ZONE /etc/localtime
  hwclock --systohc --utc
}

function set_hostname {
  log_progress "Setting hostname..."
  echo ${HOSTNAME} > /etc/hostname
}


function make_initcpio(){
  log_progress "make initcpio..."
  mkinitcpio -p linux
}


function log_progress {
  echo -e "\033[37;1;41m"[$(date +"%d/%m/%Y %k:%M:%S")]:$1 "\033[0m"
  read -p "press Enter to continue..."
}


# script body
log_progress "Arch linux installation script started..."

read_params $*

if [ ! -z $DEBUG ]; then
  log_progress "Trying to debug $DEBUG..."
  $DEBUG
  exit $?
fi

if is_chroot ;then
 stage2
else
 stage1
 chroot_install
fi 

if [ $? == 0 ]; then
  log_progress "Installation successful!"
else
  log_progress "ERROR: Installation did not complete successfully!"
fi
