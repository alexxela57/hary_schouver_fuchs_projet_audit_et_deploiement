# Supervision centralisée – Agents JSON, Prometheus, Grafana

## 1. Objectif

Ce projet prolonge la première partie d'audit système.
L'objectif est de mettre en place une supervision centralisée en réutilisant l'outil d'audit Ruby, avec la chaîne suivante :

> Agents Docker → JSON → json_exporter → Prometheus → Grafana

Les exigences principales sont :

- plusieurs conteneurs agents qui auditenent une machine Linux et exposent un fichier JSON ;
- un conteneur json_exporter qui convertit ce JSON en métriques Prometheus ;
- un conteneur Prometheus qui scrute régulièrement ces métriques ;
- un conteneur Grafana qui affiche les métriques sous forme de tableaux de bord.

Ce README décrit l'architecture, les fichiers de configuration et la procédure de déploiement, puis discute les limites et pistes d'amélioration.

---

## 2. Architecture globale

### 2.1. Vue d'ensemble

Composants principaux :

- agent_a, agent_b  
  Conteneurs Ruby basés sur l'outil d'audit développé en partie 1.  
  Ils montent le système de fichiers de l'hôte en lecture seule sous /host, collectent les métriques système (load, mémoire, disques, services) et écrivent un fichier /app/audit.json.  
  Un mini serveur HTTP (busybox httpd) permet de servir ce fichier.

- json_exporter  
  Conteneur de l'exporter JSON compatible Prometheus.  
  Il reçoit une URL cible (target=http://agent_a:9101/audit.json par exemple), lit le JSON et l'adapte en métriques Prometheus selon la configuration json_exporter/config.yml.

- prometheus  
  Scrute json_exporter en mode multi-cible.  
  Les URLs des agents (http://agent_a:9101/audit.json, http://agent_b:9102/audit.json) sont déclarées dans prometheus/prometheus.yml et transformées en métriques via le module agent.

- grafana  
  Se connecte à Prometheus grâce à une datasource provisionnée.  
  Charge automatiquement plusieurs dashboards JSON (CPU load, mémoire, disque, services, tableau de bord global).

L'ensemble des services est orchestré par docker-compose.yml dans le répertoire supervision/.

### 2.2. Schéma logique (texte)

- Machine hôte Linux  
  ↳ lance docker compose up  
  ↳ démarre agent_a, agent_b, json_exporter, prometheus, grafana.

- Chaque agent_X :
  - voit le système de fichiers hôte sous /host ;
  - génère périodiquement /app/audit.json ;
  - expose ce fichier en HTTP (port 910X).

- json_exporter :
  - reçoit des requêtes GET /probe?module=agent&target=URL_JSON ;
  - lit l'URL JSON ;
  - applique les règles définies dans config.yml pour générer des métriques.

- prometheus :
  - scrute json_exporter avec le paramètre target= pour chaque agent ;
  - stocke les séries temporelles (load, mémoire, disques, services).

- grafana :
  - interroge Prometheus ;
  - affiche des courbes et états par agent.

---

## 3. Agents d'audit

### 3.1. Docker et montage du host

Les services agent_a et agent_b sont déclarés dans docker-compose.yml.
Points importants (exemple type) :

- pid: "host"  
  Partage l'espace de PID du host. Ceci permet au script d'inspecter les processus système.

- volumes: "/:/host:ro,rslave"  
  Monte la racine / du host en lecture seule dans le conteneur sous /host.  
  Toute la collecte de données se fait à partir de ce chemin.

- cap_add: ["SYS_ADMIN"]  
  Permet certaines opérations systèmes nécessaires à l'audit (à discuter dans la section "Limites").

Chaque agent exécute une commande de ce type :

```sh
ruby /app/script_final.rb
busybox httpd -f -p 910X -h /app &

while true; do
  ruby /app/script_final.rb
  sleep "${INTERVAL:-10}"
done
```

où X = 1 pour agent_a et X = 2 pour agent_b.  
Le fichier /app/audit.json est ainsi régénéré périodiquement.

### 3.2. Script Ruby script_final.rb

Le script Ruby est une refonte de l'outil d'audit de la partie 1, adaptée à la sortie JSON.
Il s'appuie sur une constante :

```ruby
HOST = "/host"
```

Toutes les lectures système sont effectuées à l'intérieur de ce préfixe.

Les blocs fonctionnels principaux sont les suivants.

#### 3.2.1. Métadonnées (hostname, OS, noyau)

La fonction meta lit directement les métadonnées sur le host :

```ruby
def safe_read(path)
  File.read(path)
rescue
  nil
end

def run(cmd)
  output = `#{cmd} 2>/dev/null`
  $?.success? ? output.strip : nil
end

def meta
  hostname = safe_read("#{HOST}/etc/hostname")&.strip
  if hostname.nil? || hostname.empty?
    hostname = run("chroot #{HOST} hostname") || "unknown"
  end

  os_release = safe_read("#{HOST}/etc/os-release")
  os_name = if os_release
              os_release[/^PRETTY_NAME="([^"]+)"/, 1] ||
              os_release[/^NAME="([^"]+)"/, 1]
            end
  os_name ||= "unknown"

  kernel = run("chroot #{HOST} uname -r") || "unknown"

  {
    hostname: hostname,
    os: os_name,
    kernel: kernel,
    ts: Time.now.utc.strftime("%Y-%m-%d_%H:%M:%S")
  }
end
```

Cette approche garantit que les informations renvoyées correspondent à la machine auditée, et non au conteneur.

#### 3.2.2. Charge CPU (load average)

Le script lit "#{HOST}/proc/loadavg" :

```ruby
def read_load
  data = safe_read("#{HOST}/proc/loadavg")
  return { load1: 0.0, load5: 0.0, load15: 0.0 } unless data

  fields = data.split
  {
    load1:  fields[0].to_f,
    load5:  fields[1].to_f,
    load15: fields[2].to_f
  }
end
```

Cette valeur représente la charge moyenne (load average) sur 1, 5 et 15 minutes.

#### 3.2.3. Mémoire et swap

Le script lit "#{HOST}/proc/meminfo" et reconstruit les valeurs en octets :

```ruby
def read_mem
  data = safe_read("#{HOST}/proc/meminfo")
  return {} unless data

  mem = {}
  data.each_line do |line|
    if line =~ /^(\w+):\s+(\d+)\s+kB/
      mem[$1] = $2.to_i * 1024
    end
  end

  total      = mem["MemTotal"]      || 0
  available  = mem["MemAvailable"]  || 0
  swap_total = mem["SwapTotal"]     || 0
  swap_free  = mem["SwapFree"]      || 0

  used       = [total - available, 0].max
  swap_used  = [swap_total - swap_free, 0].max

  {
    total_bytes:       total,
    used_bytes:        used,
    swap_total_bytes:  swap_total,
    swap_used_bytes:   swap_used
  }
end
```

#### 3.2.4. Disques et partitions

Les points de montage sont obtenus à partir de "/proc/1/mounts" du host :

```ruby
SKIP_FS = %w[tmpfs devtmpfs overlay squashfs]

def read_disks
  mounts_content = safe_read("#{HOST}/proc/1/mounts")
  unless mounts_content
    mounts_content = run("chroot #{HOST} cat /proc/1/mounts")
  end
  return [] unless mounts_content

  disks = []

  mounts_content.each_line do |line|
    dev, mountpoint, fstype, *_ = line.split
    next if SKIP_FS.include?(fstype)

    host_mount = "#{HOST}#{mountpoint}"
    next unless File.directory?(host_mount)

    df_output = run("df -B1 --output=target,size,used "#{host_mount}" | tail -n +2")
    next unless df_output

    _, size_str, used_str = df_output.split
    disks << {
      mount:       mountpoint,
      total_bytes: size_str.to_i,
      used_bytes:  used_str.to_i
    }
  end

  disks
end
```

Les systèmes de fichiers temporaires (tmpfs, devtmpfs, etc.) sont ignorés.

#### 3.2.5. Services critiques

Une liste de noms de services est définie (sshd, cron, docker, etc.).
Le script parcourt les processus du host dans "#{HOST}/proc/[0-9]*/comm" et cmdline pour déterminer quels services sont présents.

Exemple de logique :

```ruby
SERVICE_CANDIDATES = {
  "sshd"          => ["sshd"],
  "cron"          => ["cron", "crond"],
  "docker"        => ["dockerd"],
  "network"       => ["NetworkManager", "systemd-networkd"],
  "journald"      => ["systemd-journald"]
}

def host_process_index
  index = Hash.new { |h, k| h[k] = [] }

  Dir.glob("#{HOST}/proc/[0-9]*/comm").each do |comm_path|
    pid = comm_path.split("/")[-2]
    name = safe_read(comm_path)&.strip
    next unless name

    index[name] << pid
  end

  index
end

def services_status
  index = host_process_index
  SERVICE_CANDIDATES.map do |logical_name, patterns|
    up = patterns.any? { |p| index.key?(p) } ? 1 : 0
    { name: logical_name, up: up }
  end
end
```

#### 3.2.6. Assemblage et écriture du JSON

Le script regroupe toutes ces informations sous une clé metrics :

```ruby
def build_payload
  {
    metrics: {
      meta:     meta,
      load:     read_load,
      mem:      read_mem,
      disk:     read_disks,
      services: services_status
    }
  }
end

def main
  payload = build_payload
  File.write("/app/audit.json", JSON.pretty_generate(payload))
  puts "JSON écrit: /app/audit.json"
end

main if __FILE__ == $0
```

Le fichier /app/audit.json est ensuite servi par busybox httpd.

---

## 4. json_exporter : configuration config.yml

Le fichier json_exporter/config.yml décrit comment interpréter le JSON produit par les agents.

### 4.1. Module agent

Exemple de configuration :

```yaml
modules:
  agent:
    metrics:
      - name: agent_info
        path: '{.metrics.meta}'
        help: 'Static information about the host'
        labels:
          hostname: '{.hostname}'
          kernel: '{.kernel}'
          os: '{.os}'
        value: 1

      - name: load
        path: '{.metrics.load}'
        help: 'Load average over 1, 5, 15 minutes'
        labels: {}
        values:
          load1: '{.load1}'
          load5: '{.load5}'
          load15: '{.load15}'

      - name: mem
        path: '{.metrics.mem}'
        help: 'Memory usage in bytes'
        labels: {}
        values:
          total_bytes:      '{.total_bytes}'
          used_bytes:       '{.used_bytes}'
          swap_total_bytes: '{.swap_total_bytes}'
          swap_used_bytes:  '{.swap_used_bytes}'

      - name: disk
        path: '{.metrics.disk[*]}'
        help: 'Disk usage per mountpoint'
        labels:
          mountpoint: '{.mount}'
        values:
          total_bytes: '{.total_bytes}'
          used_bytes:  '{.used_bytes}'

      - name: service
        path: '{.metrics.services[*]}'
        help: 'Service status (1 = up, 0 = down)'
        labels:
          service: '{.name}'
        values:
          up: '{.up}'
```

- path pointe vers une branche du JSON (metrics.mem, metrics.disk[*], etc.) ;
- labels sont remplis à partir des champs de cette branche ;
- values définissent les valeurs numériques exportées.

---

## 5. Prometheus : prometheus/prometheus.yml

Le scraping des agents se fait via json_exporter en mode multi-cible.

### 5.1. Job json_agents

Exemple de configuration :

```yaml
scrape_configs:
  - job_name: 'json_agents'
    metrics_path: /probe
    params:
      module: [agent]

    static_configs:
      - targets:
        - 'http://agent_a:9101/audit.json'
        - 'http://agent_b:9102/audit.json'
        labels:
          group: 'lab'

    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - target_label: __address__
        replacement: 'json_exporter:7979'
      - source_labels: [__param_target]
        target_label: instance
```

Explication :

- targets contient les URLs HTTP des JSON d'agents ;
- la première règle de relabel copie __address__ dans __param_target (URL cible JSON) ;
- la deuxième remplace __address__ par json_exporter:7979 (adresse réelle de l'exporter) ;
- la troisième expose la cible JSON dans le label instance.

### 5.2. Job json_exporter (optionnel)

Un second job peut scruter directement les propres métriques de json_exporter pour surveiller l'exporter en lui-même.

---

## 6. Grafana : datasource et dashboards

### 6.1. Datasource Prometheus

Dans grafana/provisioning/datasources/prometheus-grafana.yml :

- définition d'une datasource Prometheus ;
- URL : http://prometheus:9090 ;
- datasource par défaut (isDefault: true).

Grâce à ce provisioning, aucune configuration manuelle n'est nécessaire dans l'interface Grafana.

### 6.2. Provisioning des dashboards

Dans grafana/provisioning/dashboards/dashboards.yml :

- provider de type file ;
- dossier source /var/lib/grafana/dashboards.

Les dashboards JSON (par exemple CPU LOAD (Agent A & B).json, MEM USED (Agent A & B).json, DISK USED (Agent A & B).json, SERVICES STATUS (Agent A & B).json, AuditSystèmeComplet.json) sont déposés dans grafana/dashboards/ et importés automatiquement au démarrage.

Les panels utilisent les métriques promues (load_load1, mem_used_bytes, disk_used_bytes, service_up, etc.) et sont filtrables par instance et/ou hostname.

---

## 7. Déploiement et vérifications

### 7.1. Prérequis

- Docker et Docker Compose installés sur la machine hôte.

### 7.2. Lancement

Dans le répertoire supervision/ :

```bash
docker compose up -d
```

Services attendus :

- agent_a, agent_b
- json_exporter
- prometheus
- grafana

### 7.3. Tests rapides

1. Vérifier le JSON d'un agent

```bash
curl http://localhost:9101/audit.json
```

On doit voir un JSON avec les blocs meta, load, mem, disk, services.

2. Vérifier json_exporter

```bash
curl "http://localhost:7979/probe?module=agent&target=http://agent_a:9101/audit.json"
```

On doit obtenir un texte au format métriques Prometheus (# HELP, # TYPE, etc.).

3. Vérifier Prometheus

- Interface : http://localhost:9090/
- Onglet Status → Targets : job json_agents avec les targets agent_a et agent_b.

4. Vérifier Grafana

- Interface : http://localhost:3000/
- Connexion initiale (admin/admin si non modifié) ;
- Vérifier la présence de la datasource Prometheus et des dashboards importés.

---

## 8. Limites et perspectives

### 8.1. Limites de la solution actuelle

- Deux agents, une seule machine physique  
  Dans cette maquette, agent_a et agent_b auditent la même machine (le host).  
  Les métriques système sont donc identiques, seuls les labels diffèrent.  
  Cela reste suffisant pour démontrer le fonctionnement multi-agents.

- Accès système large  
  Les agents disposent d'un accès important au host :
  - montage de / entier en lecture seule ;
  - partage de l'espace PID ;
  - capacités élevées (SYS_ADMIN).  
  C'est acceptable pour un TP local, mais à limiter en production.

- Périmètre des métriques  
  Les métriques exposées couvrent :
  - load average (1, 5, 15) ;
  - mémoire (RAM + swap) ;
  - disques (par point de montage) ;
  - statut de quelques services critiques.  
  Les interfaces réseau, utilisateurs connectés et processus gourmands ne sont pas encore exportés en tant que métriques Prometheus (présents dans la partie 1 mais pas adaptés ici).

### 8.2. Pistes d'amélioration

- Déploiement sur plusieurs machines réelles  
  Déployer agent_a et agent_b sur des serveurs différents permettrait de comparer des machines réellement distinctes dans les dashboards.

- Réduction des privilèges  
  Limiter les montages au strict nécessaire (/proc, /etc, points de montage de disques) et réduire les capacités ajoutées afin de diminuer la surface d'attaque, tout en conservant l'audit fonctionnel.

- Extension du modèle de métriques  
  Ajouter dans le JSON puis dans config.yml :
  - des métriques sur le réseau (débits, erreurs) ;
  - des métriques sur les processus les plus gourmands (CPU, mémoire) ;
  - éventuellement des infos sur les utilisateurs connectés.

- Alternative SSH (perspective)  
  En alternative au montage de /, on pourrait imaginer un agent central qui se connecte via SSH à plusieurs machines, exécute le script d'audit à distance et agrège les JSON.  
  Cette approche n'est pas mise en œuvre ici, mais elle constitue une piste pour des environnements distribués plus réalistes.
