# Image de base compacte et à jour
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive


RUN apt-get update && apt-get install -y --no-install-recommends \
      ruby neofetch iproute2 procps gawk grep util-linux \
      openssh-client ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Répertoire d’app et de sortie
WORKDIR /app

# Copie du script Ruby (nomme-le audit.rb à côté du Dockerfile)
COPY script_final.rb /app/script_final.rb

# Point d’entrée : exécuter le script
ENTRYPOINT ["ruby", "/app/script_final.rb"]
