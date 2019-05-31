#!/usr/bin/env bash
set -e

# Arch Linux Install Script (alis) installs unattended, automated
# and customized Arch Linux system.
# Copyright (C) 2018

rm -f alis.conf
rm -f alis.sh

wget https://raw.githubusercontent.com/magdeoz/alis/master/alis.conf
wget https://raw.githubusercontent.com/magdeoz/alis/master/alis-lite.sh
wget https://raw.githubusercontent.com/magdeoz/alis/master/alis.sh

chmod +x alis.sh
