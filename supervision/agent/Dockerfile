FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Outils nécessaires : Ruby, httpd BusyBox, nsenter (util-linux), iproute2, procps...
RUN apt-get update && apt-get install -y --no-install-recommends \
    ruby busybox iproute2 procps gawk grep util-linux neofetch \
    openssh-client ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY script_final.rb /app/script_final.rb

# On laisse la commande au compose (pour démarrer httpd + loop)
