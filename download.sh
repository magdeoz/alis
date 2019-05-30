#!/usr/bin/env bash
set -e

# Arch Linux Install Script (alis) installs unattended, automated
# and customized Arch Linux system.
# Copyright (C) 2018

rm -f alis.conf
rm -f alis.sh
rm -f alis-asciinema.sh
rm -f alis-reboot.sh

rm -f alis-recovery.conf
rm -f alis-recovery.sh
rm -f alis-recovery-asciinema.sh
rm -f alis-recovery-reboot.sh

wget https://raw.githubusercontent.com/magdeoz/alis/master/alis.conf
wget https://raw.githubusercontent.com/magdeoz/alis/master/alis.sh

chmod +x alis.sh
