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
# 4. liste des utilisateurs humain (uid ⩾ 1000) existants, en distinguant ceux actuellement connectés
```
grep -E ':[1-9][0-9]{3,}:' /etc/passwd | cut -d: -f1 
users | grep "$u"
```
5.
6.
7.
8.



