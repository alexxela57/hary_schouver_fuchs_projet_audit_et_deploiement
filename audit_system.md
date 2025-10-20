# 1. nom de la machine, distribution, version du noyau
```
hostname
neofetch | grep -E "OS|Kernel"
```
# 2. uptime, charge moyenne, mémoire et swap disponibles et utilisés
```
uptime
free -h
```
# 3. liste des interfaces réseau : adresses MAC et IP associées
affiche MAC, IPv4, IPv6
```
ip a | grep -E "(link|inet)"
```
# 4. liste des utilisateurs humain existants, en distinguant ceux actuellement connectés
```
grep -E '^[^:]*:[^:]*:[1-9][0-9]{3,}:' /etc/passwd | cut -d: -f1 
users | grep "$u"
```
# 5. espace disque par partition (disponible, utilisé)
df pour afficher les partitions et -h pour afficher en Go
```
df -h -x tmpfs -x devtmpfs --output=source,size,used,avail,pcent
```
# 6. processus les plus consommateurs de CPU et de mémoire 
```
ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu | awk '$4+0 > 5.0 &&  $5+0 > 5.0'

```
# 7. processus les plus consommateurs de trafic réseau
```
sudo nethogs -t -C -d 1 -c 10
```

# 8.présence et statut de certains services clés 
```
systemctl --no-pager --type=service --all | grep -E 'sshd|cron|docker|NetworkManager|systemd-networkd|rsyslog|systemd-journald|firewalld|ufw|nginx|apache2|httpd|mariadb|mysqld|postgresql'

```



