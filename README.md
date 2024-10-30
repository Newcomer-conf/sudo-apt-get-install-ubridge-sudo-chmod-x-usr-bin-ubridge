# 
alt server 10
1) su -
2) echo "root    ALL=(ALL:ALL) ALL" >> /etc/sudoers
3) echo "admin    ALL=(ALL:ALL) ALL" >> /etc/sudoers  (admin username)

4) exit
5) sudo apt-get update
6) sudo apt-get install git -y
7) sudo git clone https://github.com/Newcomer-conf/tes_789.git
8) cp tes_789/auto-config-gns3-alt-server-10.sh /home/admin
9) sudo rm -r  tes_789 
10) sudo bash auto-config-gns3-alt-server-10.sh
