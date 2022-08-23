#!/bin/bash
#
# Copyright 2020 Karl Stenerud, released under MIT license (see README.md) (Original)
# Copyright 2022 Mateusz Chruściel, original script modified and released under MIT license (see README.md) (Fork)
#
# This script installs Ubuntu Server with a ZFS mirror root. It must be launched from
# a running Linux "bootstrap" system (tested with the Ubuntu live CD) (tested with the Ubuntu 20.04 live CD).
#
# WARNING: It is highly recommended to use corresponding live CD to OS version being installed!
#
# WARNING: This will overwrite the disk specified by $CFG_DISK* without asking!
#
# Optional: Install SSHD in the live CD session to run over SSH:
#   sudo apt install --yes openssh-server vim && echo -e "ubuntu\nubuntu" | passwd ubuntu

set -eux

# Configuration
# -------------

# Identifier to use when creating zfs data sets (default: random).
CFG_ZFSID=$(dd if=/dev/urandom of=/dev/stdout bs=1 count=100 2>/dev/null | tr -dc 'a-z0-9' | cut -c-6)

# ATTENTION
# The disk to partition. On a real machine, this should be /dev/disk/by-id/xyz.
CFG_DISK1=/dev/disk/by-path/
CFG_DISK2=/dev/disk/by-path/

# The ethernet device to use
CFG_ETH=

# The host's name
CFG_HOSTNAME=

# The user to create. Password will be the same as the name.
CFG_USERNAME=ubuntu

# The time zone to set
CFG_TIMEZONE=Europe/Warsaw

# Where to get the debs from
CFG_ARCHIVE=http://pl.archive.ubuntu.com/ubuntu/

# Which Ubuntu version to install (focal=20.04, jammy=22.04, etc)
CFG_UBUNTU_VERSION=focal

# Vars
# ----

has_uefi=$([ -d /sys/firmware/efi ] && echo true || echo false)

# Prepare software
# ----------------

apt-add-repository universe --yes
apt update
apt install --yes debootstrap gdisk zfs-initramfs dosfstools
systemctl stop zed

# Remove leftovers from failed script (if any)
# --------------------------------------------

umount -l /mnt/dev 2>/dev/null || true
umount -l /mnt/proc 2>/dev/null || true
umount -l /mnt/sys 2>/dev/null || true
umount -l /mnt 2>/dev/null || true
swapoff --all 2>/dev/null || true
zpool destroy bpool 2>/dev/null | true
zpool destroy rpool 2>/dev/null | true

# Partitions DISK 1
# ----------
sgdisk --zap-all $CFG_DISK1
# Bootloader partition (UEFI)
sgdisk     -n1:1M:+512M   -t1:EF00 $CFG_DISK1
# Boot pool partition
sgdisk     -n2:0:+2G      -t2:BE00 $CFG_DISK1
if [ ! "$has_uefi" == true ]; then
  sgdisk -a1 -n4:24K:+1000K -t4:EF02 $CFG_DISK1
fi
# Root pool partition
sgdisk     -n3:0:0        -t3:BF00 $CFG_DISK1

sleep 1

# Partitions DISK 1
# ----------
sgdisk --zap-all $CFG_DISK2
# Bootloader partition (UEFI)
sgdisk     -n1:1M:+512M   -t1:EF00 $CFG_DISK2
# Boot pool partition
sgdisk     -n2:0:+2G      -t2:BE00 $CFG_DISK2
if [ ! "$has_uefi" == true ]; then
  sgdisk -a1 -n4:24K:+1000K -t4:EF02 $CFG_DISK2
fi
# Root pool partition
sgdisk     -n3:0:0        -t3:BF00 $CFG_DISK2

sleep 1

# EFI
mkdosfs -F 32 -s 1 -n EFI ${CFG_DISK1}-part1
mkdosfs -F 32 -s 1 -n EFI ${CFG_DISK2}-part1

# Boot pool
zpool create -f \
    -o ashift=12 -d \
    -o feature@async_destroy=enabled \
    -o feature@bookmarks=enabled \
    -o feature@embedded_data=enabled \
    -o feature@empty_bpobj=enabled \
    -o feature@enabled_txg=enabled \
    -o feature@extensible_dataset=enabled \
    -o feature@filesystem_limits=enabled \
    -o feature@hole_birth=enabled \
    -o feature@large_blocks=enabled \
    -o feature@lz4_compress=enabled \
    -o feature@spacemap_histogram=enabled \
    -o feature@zpool_checkpoint=enabled \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=lz4 \
    -O devices=off \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=/boot -R /mnt \
    bpool mirror \
    ${CFG_DISK1}-part2 \
    ${CFG_DISK2}-part2

zfs create -o canmount=off -o mountpoint=none bpool/BOOT

# Root pool
zpool create -f \
    -o ashift=12 \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=lz4 \
    -O dnodesize=auto \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=/ -R /mnt \
    rpool mirror \
    ${CFG_DISK1}-part3 \
    ${CFG_DISK2}-part3

zfs create -o canmount=off -o mountpoint=none rpool/ROOT

# /
zfs create \
    -o canmount=noauto \
    -o mountpoint=/ \
    -o com.ubuntu.zsys:bootfs=yes \
    -o com.ubuntu.zsys:last-used=$(date +%s) rpool/ROOT/ubuntu_$CFG_ZFSID
zfs mount rpool/ROOT/ubuntu_$CFG_ZFSID

zfs create \
    -o canmount=off \
    -o mountpoint=/ rpool/USERDATA

zfs create \
    -o com.ubuntu.zsys:bootfs-datasets=rpool/ROOT/ubuntu_$CFG_ZFSID \
    -o canmount=on \
    -o mountpoint=/root rpool/USERDATA/root_$CFG_ZFSID

# /boot
zfs create \
    -o canmount=noauto \
    -o mountpoint=/boot bpool/BOOT/ubuntu_$CFG_ZFSID
zfs mount bpool/BOOT/ubuntu_$CFG_ZFSID

# /boot/grub for mirror
zfs create -o com.ubuntu.zsys:bootfs=no bpool/grub

# /home/user
zfs create \
    -o com.ubuntu.zsys:bootfs-datasets=rpool/ROOT/ubuntu_$CFG_ZFSID \
    -o canmount=on \
    -o mountpoint=/home/$CFG_USERNAME rpool/USERDATA/$CFG_USERNAME

# /srv
zfs create \
    -o com.ubuntu.zsys:bootfs=no rpool/ROOT/ubuntu_$CFG_ZFSID/srv

# /tmp
zfs create \
    -o com.ubuntu.zsys:bootfs=no rpool/ROOT/ubuntu_$CFG_ZFSID/tmp

chmod 1777 /mnt/tmp

# /usr
zfs create \
    -o com.ubuntu.zsys:bootfs=no \
    -o canmount=off rpool/ROOT/ubuntu_$CFG_ZFSID/usr

zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/usr/local

# /var
zfs create \
    -o com.ubuntu.zsys:bootfs=no \
    -o canmount=off rpool/ROOT/ubuntu_$CFG_ZFSID/var

zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/var/games
zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/var/lib
zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/var/lib/AccountsService
zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/var/lib/apt
zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/var/lib/dpkg
zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/var/lib/NetworkManager
zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/var/log
zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/var/mail
zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/var/snap
zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/var/spool
zfs create rpool/ROOT/ubuntu_$CFG_ZFSID/var/www

# Bootstrap
# ---------

debootstrap $CFG_UBUNTU_VERSION /mnt

cat <<BOOTSTRAP2_SH_EOF >/mnt/root/bootstrap2.sh
#!/bin/bash
set -eux
# Locale/TZ
echo "locales locales/default_environment_locale select en_US.UTF-8" | debconf-set-selections
echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" | debconf-set-selections
rm -f "/etc/locale.gen"
dpkg-reconfigure --frontend noninteractive locales
ln -fs /usr/share/zoneinfo/$CFG_TIMEZONE /etc/localtime
dpkg-reconfigure --frontend noninteractive tzdata
# Configuration
echo $CFG_HOSTNAME > /etc/hostname
echo "127.0.1.1       $CFG_HOSTNAME" >> /etc/hosts
cat >/etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $CFG_ETH:
      dhcp4: true
EOF
cat >/etc/apt/sources.list <<EOF
deb $CFG_ARCHIVE $CFG_UBUNTU_VERSION main restricted universe multiverse
deb $CFG_ARCHIVE $CFG_UBUNTU_VERSION-updates main restricted universe multiverse
deb $CFG_ARCHIVE $CFG_UBUNTU_VERSION-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $CFG_UBUNTU_VERSION-security main restricted universe multiverse
EOF
apt update
# EFI
mkdir /boot/efi
echo UUID=$(blkid -s UUID -o value ${CFG_DISK1}-part1) \
  /boot/efi vfat umask=0022,fmask=0022,dmask=0022 0 1 >> /etc/fstab
mount /boot/efi
if [ "$has_uefi" == true ]; then
  apt install --yes grub-efi-amd64 grub-efi-amd64-signed linux-image-generic shim-signed zfs-initramfs zsys
else
  # Note: grub-pc will ask where to write
  apt install --yes grub-pc linux-image-generic zfs-initramfs zsys
fi
dpkg --purge os-prober
# System groups
addgroup --system lpadmin
# GRUB
grub-probe /boot
update-initramfs -c -k all
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 init_on_alloc=0"/g' /etc/default/grub
update-grub
if [ "$has_uefi" == true ]; then
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck --no-floppy
else
  grub-install $CFG_DISK1
  grub-install $CFG_DISK2
fi
systemctl mask grub-initrd-fallback.service
## FS mount ordering
mkdir /etc/zfs/zfs-list.cache
touch /etc/zfs/zfs-list.cache/bpool
touch /etc/zfs/zfs-list.cache/rpool
ln -sf /usr/lib/zfs-linux/zed.d/history_event-zfs-list-cacher.sh /etc/zfs/zed.d
zed -F &
zed_pid=\$!
sleep 5
kill \$zed_pid
sed -Ei "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/*
# Install GRUB to additional disks
if [ "$has_uefi" == true ]; then
  dpkg-reconfigure --frontend noninteractive grub-efi-amd64
fi
# Add user
adduser --disabled-password --gecos "" $CFG_USERNAME
cp -a /etc/skel/. /home/$CFG_USERNAME
chown -R $CFG_USERNAME:$CFG_USERNAME /home/$CFG_USERNAME
usermod -a -G adm,cdrom,dip,lpadmin,plugdev,sudo $CFG_USERNAME
echo -e "$CFG_USERNAME\n$CFG_USERNAME" | passwd $CFG_USERNAME
# Install ssh
apt dist-upgrade --yes
apt install --yes openssh-server vim nano
# Disable logrotote compression since zfs does that already
for file in /etc/logrotate.d/* ; do
    if grep -Eq "(^|[^#y])compress" "\$file" ; then
        sed -i -r "s/(^|[^#y])(compress)/\1#\2/" "\$file"
    fi
done
BOOTSTRAP2_SH_EOF
chmod a+x /mnt/root/bootstrap2.sh

mount --rbind /dev  /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys  /mnt/sys
chroot /mnt /usr/bin/env \
  has_uefi=$has_uefi \
  CFG_DISK1=$CFG_DISK1 \
  CFG_DISK2=$CFG_DISK2 \
  CFG_HOSTNAME=$CFG_HOSTNAME \
  CFG_USERNAME=$CFG_USERNAME \
  CFG_ETH=$CFG_ETH \
  CFG_TIMEZONE=$CFG_TIMEZONE \
  CFG_ARCHIVE=$CFG_ARCHIVE \
  CFG_UBUNTU_VERSION=$CFG_UBUNTU_VERSION \
  bash --login /root/bootstrap2.sh
rm /mnt/root/bootstrap2.sh

# Installation finisher script
# ----------------------------

cat <<FINISH_INSTALL_SH_EOF >/mnt/home/$CFG_USERNAME/finish-install.sh
#!/bin/bash
set -eux
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
  ubuntu-standard \
  ubuntu-server \
  apt-transport-https \
  avahi-daemon \
  ca-certificates \
  curl \
  git \
  gnupg-agent \
  net-tools \
  nmap \
  software-properties-common \
  telnet \
  tree
sudo apt dist-upgrade -y
sudo zfs snapshot rpool/ROOT/ubuntu_$CFG_ZFSID@fresh-install
echo "Installation complete. Delete /home/$CFG_USERNAME/finish-install.sh and reboot."
FINISH_INSTALL_SH_EOF
chmod a+x /mnt/home/$CFG_USERNAME/finish-install.sh
chown 1000:1000 /mnt/home/$CFG_USERNAME/finish-install.sh

# Clean up
# --------

umount -l /mnt/dev 2>/dev/null || true
umount -l /mnt/proc 2>/dev/null || true
umount -l /mnt/sys 2>/dev/null || true
umount -l /mnt 2>/dev/null || true
zpool export bpool
zpool export rpool

echo "Bootstrap complete. Please reboot, remove the installer medium, and then run /home/$CFG_USERNAME/finish-install.sh"
