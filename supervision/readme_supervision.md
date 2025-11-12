# Supervision centralisée — Agents JSON → json_exporter → Prometheus → Grafana

> Version finale, conforme au sujet « pré‑SAE 2 ». Inclut maquette locale **et** déploiement multi‑machines, renommage de la métrique de charge, métadonnées lues sur le host, provisioning Grafana, et vérifications.

---

## 1) Objectif
Mettre en place une **supervision centralisée** de systèmes Linux en réutilisant l’outil d’audit Ruby :

```
Agents Docker  →  JSON  →  json_exporter  →  Prometheus  →  Grafana
```

Exigences couvertes :
- ≥2 conteneurs **agents** qui auditent une machine Linux et exposent un **fichier JSON**.
- **json_exporter** convertit ce JSON en métriques Prometheus.
- **Prometheus** scrute régulièrement ces métriques (pattern « multi‑target exporter »).
- **Grafana** est provisionné (datasource + dashboards) et affiche CPU load, mémoire, disque, services, et un tableau de bord global.

---

## 2) Architecture

### 2.1 Vue d’ensemble
- **agent_X** (Ruby) : monte le système de fichiers **du host** en lecture seule sous `/host`, collecte `load`, `mem`, `disk`, `services`, écrit `/app/audit.json`, le sert via HTTP.
- **json_exporter** : lit une **URL JSON** et expose des métriques Prometheus selon `json_exporter/config.yml`.
- **Prometheus** : scrute `json_exporter` en lui passant la cible (`target=<URL JSON>`), ajoute des labels (`instance`, `group`, …).
- **Grafana** : datasource Prometheus provisionnée, dashboards provisionnés.

### 2.2 Schéma (texte)
- Hôte Linux (ou plusieurs hôtes)
  - lance `docker compose up`
  - démarre : `agent_*`, `json_exporter`, `prometheus`, `grafana`
- Chaque **agent**
  - voit le host sous `/host`
  - régénère périodiquement `/app/audit.json`
  - publie `http://<agent>:910X/audit.json`
- **json_exporter** : `/probe?module=agent&target=http://<agent>:910X/audit.json`
- **Prometheus** : stocke les séries
- **Grafana** : affiche et compare par `instance` / `hostname`

---

## 3) Deux modes de déploiement

### Mode A — **Maquette locale** (2 agents sur un seul host)
- `agent_a` et `agent_b` tournent sur **le même hôte** (utile pour démontrer le multi‑agents rapidement).
- Les métriques système seront identiques, seuls les labels diffèrent ; c’est acceptable pour la soutenance.

### Mode B — **Multi‑machines** (recommandé si possible)
1. **Sur chaque machine distante** (hostA, hostB), déployer **uniquement l’agent** :
   ```yaml
   # agent-only.compose.yml
   services:
     agent:
       build: ./agent          # ou image: your/agent:tag
       pid: "host"
       cap_add: ["SYS_ADMIN"]
       volumes:
         - /:/host:ro,rslave
       ports:
         - "9101:9101"        # sert /app/audit.json
       command: >
         sh -c "ruby /app/script_final.rb && \
                busybox httpd -f -p 9101 -h /app & \
                while true; do ruby /app/script_final.rb; sleep ${INTERVAL:-10}; done"
   ```
   Lancer sur chaque machine :
   ```bash
   docker compose -f agent-only.compose.yml up -d
   ```
   Vérifier depuis la machine centrale :
   ```bash
   curl http://<IP_hostA>:9101/audit.json
   curl http://<IP_hostB>:9101/audit.json
   ```

2. **Sur la machine centrale** : conserver `json_exporter`, `prometheus`, `grafana` et déclarer les cibles **externes** dans `prometheus.yml` (cf. §5.1).

> Remarque : on peut remplacer `ports:` par `network_mode: "host"` côté agent si l’environnement l’exige. Dans ce cas, ne mappez pas les ports.

---

## 4) Agent d’audit (Ruby)

### 4.1 Principe
- Toutes les lectures se font **dans `/host`** pour auditer le système hôte, pas le conteneur.
- Sortie : fichier `/app/audit.json` au format :
  ```json
  {
    "metrics": {
      "meta":     { "hostname": "...", "os": "...", "kernel": "...", "ts": "UTC" },
      "load":     { "load1": 0.00, "load5": 0.00, "load15": 0.00 },
      "mem":      { "total_bytes": 0, "used_bytes": 0, "swap_total_bytes": 0, "swap_used_bytes": 0 },
      "disk":     [ { "mount": "/", "total_bytes": 0, "used_bytes": 0 }, ... ],
      "services": [ { "name": "sshd", "up": 1 }, ... ]
    }
  }
  ```

### 4.2 Métadonnées **lues sur le host**
- `hostname` : `/host/etc/hostname` ou `chroot /host hostname`
- `os` : `/host/etc/os-release` (`PRETTY_NAME` ou `NAME`)
- `kernel` : `chroot /host uname -r`

### 4.3 Charge, mémoire, disques, services
- **Load** : `/host/proc/loadavg` → `load1|5|15`
- **Mémoire** : `/host/proc/meminfo` → `total_bytes`, `used_bytes`, `swap_*`
- **Disques** : `/host/proc/1/mounts` → filtrage `tmpfs devtmpfs overlay squashfs` → `df -B1` sur `"#{HOST}#{mountpoint}"`
- **Services** : scan de `/host/proc/*/comm`/`cmdline` pour motifs (`sshd`, `cron|crond`, `dockerd`, `NetworkManager|systemd-networkd`, `systemd-journald`)

> Le script n’a pas besoin d’un « mode console ». Il écrit directement `audit.json` et logge une ligne « JSON écrit: /app/audit.json ».

---

## 5) json_exporter

### 5.1 Module `agent` (JSON → métriques)
`json_exporter/config.yml` :
```yaml
modules:
  agent:
    metrics:
      - name: agent_info
        path: '{.metrics.meta}'
        help: 'Static information about the host'
        labels:
          hostname: '{.hostname}'
          kernel:   '{.kernel}'
          os:       '{.os}'
        value: 1

      - name: load
        path: '{.metrics.load}'
        help: 'Load average over 1, 5, 15 minutes'
        labels: {}
        values:
          load1:  '{.load1}'
          load5:  '{.load5}'
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
> La métrique s’appelle **`load_*`** (plus clair que `cpu_*` qui prêterait à confusion). Les dashboards ont été nommés en conséquence « CPU Load (loadavg) ».

---

## 6) Prometheus

### 6.1 Scraping multi‑cible via `json_exporter` (pattern « multi‑target »)
`prometheus/prometheus.yml` :
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

  # Optionnel : surveiller l’exporter lui‑même
  - job_name: 'json_exporter'
    static_configs:
      - targets: ['json_exporter:7979']
```

### 6.2 Cibles distantes (mode **multi‑machines**)
- Remplacer `agent_a/agent_b` par des URLs externes :
  ```yaml
  - targets:
    - 'http://<IP_hostA>:9101/audit.json'
    - 'http://<IP_hostB>:9101/audit.json'
  ```
- Garder le même `relabel_configs`. `instance` contiendra l’URL JSON cible.

---

## 7) Grafana

### 7.1 Datasource
Provisionnée dans `grafana/provisioning/datasources/prometheus-grafana.yml` :
- type : Prometheus
- URL : `http://prometheus:9090`
- `isDefault: true`

### 7.2 Dashboards
- Fichiers JSON placés dans `grafana/dashboards/` et déclarés par `grafana/provisioning/dashboards/dashboards.yml` (provider `file`).
- Panneaux : **CPU Load (loadavg)**, **Memory Used**, **Disk Used**, **Services Status**, **Audit Système Complet**.
- Variables de filtre : `instance`, `hostname`.

---

## 8) Lancement & vérifications

### 8.1 Démarrer
```bash
# depuis supervision/
docker compose up -d
```

### 8.2 Tests rapides
- JSON agent :
  ```bash
  curl http://localhost:9101/audit.json
  ```
- json_exporter (probe) :
  ```bash
  curl "http://localhost:7979/probe?module=agent&target=http://agent_a:9101/audit.json"
  ```
- Prometheus : `http://localhost:9090/` → **Status → Targets** → job `json_agents` en **UP**
- Grafana : `http://localhost:3000/` → dashboards provisionnés

---

## 9) Sécurité, limites, perspectives

### 9.1 Sécurité / isolement
- Les agents ont un accès large au host : `pid: host`, `cap_add: SYS_ADMIN`, montage de `/` en lecture seule.
- Acceptable pour un TP local. En production : limiter les capacités, monter seulement `/proc`, `/etc`, et les volumes utiles.

### 9.2 Limites
- **Maquette locale** : 2 agents sur le même host ⇒ métriques identiques (labels différents).
- Périmètre métriques : load, mémoire, disques, services. Le réseau détaillé ou les top‑process ne sont pas exportés ici.

### 9.3 Pistes
- Déployer les agents sur **plusieurs hôtes** réels (mode B).
- Étendre le JSON + `config.yml` : métriques réseau, top CPU/MEM, utilisateurs connectés.
- Alternative (perspective) : un « collecteur central » qui interroge plusieurs hôtes via SSH et agrège des JSON.

---

## 10) Références
- Multi‑target exporter (Prometheus) : https://prometheus.io/docs/guides/multi-target-exporter/
- Blackbox exporter : exemple de relabel `__param_target` : https://github.com/prometheus/blackbox_exporter#prometheus-configuration
- json_exporter (JSONPath, modules/metrics) : https://github.com/prometheus-community/json_exporter
- Provisioning Grafana (datasources, dashboards) : https://grafana.com/docs/grafana/latest/administration/provisioning/
- Docker : ports publiés et mode `host` : https://docs.docker.com/engine/network/  et  https://docs.docker.com/engine/network/drivers/host/

