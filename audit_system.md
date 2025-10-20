# 1. nom de la machine, distribution, version du noyau
```
hostname
fastfetch | grep -E "(OS|Kernel):"
```
# 2. uptime, charge moyenne, mémoire et swap disponibles et utilisés
```
uptime
free -h
```
# 3. liste des interfaces réseau : adresses MAC et IP associées
affiche MAC, IPv4, IPv6
```
ip a | grep -E "link|inet"
```
4.
5.
6.
7.



