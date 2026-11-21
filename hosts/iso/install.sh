# shellcheck disable=SC2148
# run-install HOSTNAME [DRIVE]
#
# Erases DRIVE, installs the flake's HOSTNAME onto it and leaves the
# configuration in the new home directory. Run it as root from the
# installer image, which carries the flake in /iso/cfg.
user=__USER__
src=/iso/cfg
cfg=/tmp/cfg
root=/mnt

hostname=${1-}
drive=${2:-/dev/nvme0n1}

if [ ! -f "$src/hosts/$hostname/disks.nix" ]; then
  echo "usage: run-install HOSTNAME [DRIVE]" >&2
  printf 'hosts:' >&2
  for dir in "$src"/hosts/*/; do
    [ -f "$dir/disks.nix" ] && printf ' %s' "$(basename "$dir")" >&2
  done
  echo >&2
  exit 2
fi
if [ "$(id -u)" != 0 ]; then
  echo "run-install: run it as root (sudo run-install $*)" >&2
  exit 1
fi
if [ ! -b "$drive" ]; then
  echo "run-install: $drive is not a disk. The disks here:" >&2
  lsblk --nodeps --output NAME,SIZE,MODEL >&2
  exit 2
fi

lsblk --output NAME,SIZE,MODEL,FSTYPE "$drive"
read -r -p "Erase $drive and install $hostname on it? [y/N] " answer
if [ "$answer" != y ]; then
  echo "Nothing was changed." >&2
  exit 1
fi

rm -rf "$cfg"
cp -R "$src" "$cfg"
chmod -R u+w "$cfg"

echo "Generating the hardware configuration"
nixos-generate-config --dir "$cfg/hosts/$hostname" --no-filesystems

echo "Partitioning $drive and installing NixOS"
disko-install --flake "$cfg#$hostname" --disk main "$drive" --write-efi-boot-entries

# disko-install unmounts the new system when it's done. Mount it again, as
# the host's disks.nix lays it out, to finish inside it.
echo "Mounting the new system"
DISKO_SKIP_SWAP=1 disko --mode mount --root-mountpoint "$root" --flake "$cfg#$hostname"

echo "Copying the configuration to /home/$user/nix-config"
mkdir -p "$root/home/$user"
cp -R "$cfg" "$root/home/$user/nix-config"
nixos-enter --root "$root" -c "chown -R $user:users /home/$user && chmod 700 /home/$user"

echo "Setting the password for $user"
nixos-enter --root "$root" -c "passwd $user"

# Hibernation resumes from the swapfile's offset on the disk, which the
# host's configuration.nix carries as a kernel parameter.
swapfile=$root/.swapvol/swapfile
if [ -f "$swapfile" ]; then
  offset=$(btrfs inspect-internal map-swapfile -r "$swapfile")
  if ! grep -q "resume_offset=$offset\"" "$cfg/hosts/$hostname/configuration.nix"; then
    echo
    echo "Hibernation: this swapfile's offset is $offset. Set resume_offset=$offset"
    echo "in hosts/$hostname/configuration.nix and rebuild, or it won't resume."
  fi
fi

umount -R "$root"
echo
echo "Installed. Take out the installer and reboot."
