#!/bin/bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y open-iscsi
sudo systemctl enable iscsid
sudo systemctl start iscsid

# Add cgroup fix if not present
if ! grep -q "cgroup_memory=1" /boot/firmware/cmdline.txt; then
  sudo sed -i 's/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt
fi

echo "Setup complete. Rebooting in 5 seconds..."
sleep 5
sudo reboot now