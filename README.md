# Audit système Linux

Liste de commandes dans le but de dresser l’état d’une machine Linux : identité, charge, réseau, comptes, stockage, services et « top talkers » CPU/Mémoire/Réseau. 

---

## Sommaire

1. [Nom de la machine, distribution, noyau](#sec-1-nom-de-la-machine-distribution-noyau)  
2. [Uptime, charge, mémoire & swap](#sec-2-uptime-charge-memoire-swap)  
3. [Interfaces réseau, MAC, IPv4/IPv6](#sec-3-interfaces-reseau-mac-ipv4-ipv6)  
4. [Comptes humains & connexions actives](#sec-4-comptes-humains-connexions-actives)  
5. [Espace disque par partition](#sec-5-espace-disque-par-partition)  
6. [Processus gourmands CPU/Mémoire](#sec-6-processus-gourmands-cpu-memoire)  
7. [Processus gourmands en réseau](#sec-7-processus-gourmands-en-reseau)  
8. [Services clés — présence & statut](#sec-8-services-cles-presence-statut)  

---

<a id="sec-1-nom-de-la-machine-distribution-noyau"></a>
## 1) Nom de la machine, distribution, noyau

```bash
neofetch --stdout | grep -P '^\s*\w+@(.+)$|^OS:|^Kernel:'
```

*Affiche l’utilisateur@hôte, l’OS et la version du noyau dans un format lisible. Nous avons fait le choix d'utiliser neofetch puisque fastfetch n'est pas disponible sur toutes les distributions. Plutôt que d'utiliser plusieurs commandes, on a décidé de recourir à un expression régulière.*

- L’option --stdout (“standard output”) force neofetch à envoyer une version textuelle, brute et propre des infos vers la sortie standard, sans les couleurs ni les graphismes.

- L’option -P active le moteur d’expressions régulières Perl

---

<a id="sec-2-uptime-charge-memoire-swap"></a>
## 2) Uptime, charge, mémoire & swap

```bash
uptime
free -h | awk '{print $1, $2, $3}'
```

*`uptime` donne l’heure, la durée depuis le démarrage, le nombre d’utilisateurs connectés et les charges moyennes 1/5/15 min. `free` résume la RAM et le swap utilisés/disponibles. La commande awk permet de formater l'affichage.*

---

<a id="sec-3-interfaces-reseau-mac-ipv4-ipv6"></a>
## 3) Interfaces réseau : MAC, IPv4, IPv6

```bash
ip a | grep -E "(link|inet|: )"
```

*`ip a` liste les adresses et propriétés des interfaces (IPv4/IPv6) + MAC.*  
*Nous avons fait le choix de parser l'affichage du résultat de la regex sur les adresses IP et MAC puis de le filtrer dans le script Ruby.*

---

<a id="sec-4-comptes-humains-connexions-actives"></a>
## 4) Comptes humains & connexions actives

```bash
# Comptes "humains" (UID >= 1000)
grep -E '^[^:]*:[^:]*:[1-9][0-9]{3,}:' /etc/passwd | cut -d: -f1

# Utilisateurs actuellement connectés
users | grep "$u"
```

*Nous avons fait le choix d'utiliser une regex pour récupérer la ligne des users humains, puis utiliser cut afin de ne garder que le nom.*

*`users` affiche les logins présents sur le système à l’instant T (sessions ouvertes).*

- -E dans grep active un autre type de moteur de regex : les expressions régulières étendues

- cut -d: -f1 prend chaque ligne du fichier, la découpe selon : et n’affiche que le premier morceau.

---

<a id="sec-5-espace-disque-par-partition"></a>
## 5) Espace disque par partition

```bash
df -h -x tmpfs -x devtmpfs --output=source,pcent,size,used,avail | tail -n +2 | sort -k2 -nr
```

*`df` rapporte l’espace utilisé/disponible sur les systèmes de fichiers montés ; ici, on masque `tmpfs`/`devtmpfs` et on affiche les colonnes essentielles avec le pourcentage des partitions dans l'ordre décroissant.*


- Montre uniquement les colonnes souhaitées (--output=source,pcent,size,used,avail)

- Supprime la ligne d’en-tête (tail -n +2)

- Trie les systèmes de fichiers selon leur taux d’occupation décroissant (sort -k2 -nr)

---

<a id="sec-6-processus-gourmands-cpu-memoire"></a>
## 6) Processus les plus gourmands CPU/Mémoire

```bash
ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu | awk '$6 > 0.0 && $7 > 2.0'
```

*`ps` dresse un instantané des processus ; tri par CPU décroissant, puis filtrage simple (> 0 % CPU **et** > 5 % RAM).*

- -e affiche tous les processus
- -o permet de choisir les colonnes à afficher
- --sort=-%cpu trier selon la colonne % d'utilisation CPU des processus

---

<a id="sec-7-processus-gourmands-en-reseau"></a>
## 7) Processus les plus gourmands en trafic réseau

```bash
sudo nethogs -t -C -d 1 -c 10
```

*NetHogs regroupe la bande passante **par processus** (mode texte, rafraîchi toutes les 1 s, 10 itérations). Requiert des privilèges élevés.*

*On aurait pu utiliser tcptop pour monitorer les performances réseau du système à un niveau noyau mais cet outil n'est pas disponible sur toutes les distribution.*

- -c 10 : 10 itérations
- -d 1 : délai entre chaque itération
- -C afficher les valeurs de débit cumulée
- -t affiche les données en texte brut

---

<a id="sec-8-services-cles-presence-statut"></a>
## 8) Présence et statut de services clés

```bash
systemctl --no-pager --type=service --all | grep -E 'sshd|cron|docker|NetworkManager|systemd-networkd|rsyslog|systemd-journald|firewalld|ufw|nginx|apache2|httpd|mariadb|mysqld|postgresql'
```

*`systemctl` permet d’inspecter l’état des services `systemd` (chargé, actif/inactif, échec).*

- --no-pager la sortie est envoyée directement au terminal stdout

---

### Astuces

- Affichage réseau plus lisible : `ip -c a | grep -E "(link|inet|: )"` (MAC) + (IPv4/IPv6)  
- Pour ne montrer **que** le top CPU *ou* le top RAM, ajuster le tri/filtre :  
  ```bash
  ps -eo pid,user,comm,%cpu --sort=-%cpu | head -n 15
  ps -eo pid,user,comm,%mem --sort=-%mem | head -n 15
  ```

---

### Lancer le projet via Docker

- Build l'image

```
docker build -t audit-linux .
```

- Lancer le docker 

```
docker run --rm --pid=host --network=host -v /var/run/utmp:/var/run/utmp:ro -v /etc/passwd:/etc/passwd:ro -v "$PWD":/app audit-linux
```

---


### 🐳 Dockerfile 

Ce **Dockerfile** crée une image légère basée sur **Debian Bookworm
Slim** pour exécuter un script Ruby sur la machine hôte du client.

------------------------------------------------------------------------

## 🔧 Étapes principales

1.  **Image de base**

    ``` dockerfile
    FROM debian:bookworm-slim
    ```

    Utilise une version minimaliste de Debian pour réduire la taille
    finale de l'image.

2.  **Configuration non interactive**

    ``` dockerfile
    ENV DEBIAN_FRONTEND=noninteractive
    ```

    Empêche les invites interactives lors de l'installation des paquets, pour des builds automatiques.

3.  **Installation des dépendances**

    ``` dockerfile
    RUN apt-get update && apt-get install -y --no-install-recommends          ruby neofetch nethogs iproute2 procps gawk grep util-linux          openssh-client ca-certificates &&        rm -rf /var/lib/apt/lists/*
    ```

    Installe les outils essentiels :

    -   **ruby** : pour exécuter le script Ruby\
    -   **neofetch**, **nethogs**, **iproute2**, **procps** : outils
        système et réseau\
    -   **grep**, **gawk**, **util-linux** : manipulation de texte et
        processus\
    -   **openssh-client**, **ca-certificates** : communications
        sécurisées\
        Le cache APT est ensuite supprimé pour alléger l'image.

4.  **Répertoire de travail**

    ``` dockerfile
    WORKDIR /app
    ```

    Définit le répertoire principal où sera copié et exécuté le script.

5.  **Copie du script Ruby**

    ``` dockerfile
    COPY script_final.rb /app/script_final.rb
    ```

    Ajoute le script Ruby dans le conteneur.

6.  **Point d'entrée**

    ``` dockerfile
    ENTRYPOINT ["ruby", "/app/script_final.rb"]
    ```

    Définit le script Ruby comme commande principale du conteneur.
