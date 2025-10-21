#!/usr/bin/env ruby
# encoding: UTF-8

# Affiche l'espace disque par partition, trié par ordre décroissant de la colonne Uti%
puts "Sys. de fichiers Uti% Taille Utilisé Dispo"
puts `df -h -x tmpfs -x devtmpfs --output=source,pcent,size,used,avail | tail -n +2 | sort -k2 -nr`
