#!/usr/bin/env ruby
# encoding: UTF-8

# Charge la lib standard 'Open3' pour exécuter des commandes externes
# et capturer séparément stdout, stderr et le statut. 
require 'open3'

# Tableau d’arguments (évite l’expansion par le shell).
# Lance nethogs en mode trace (-t),
# avec TCP+UDP (-C), rafraîchissement 1s (-d 1), pour 10 cycles (-c 10).
cmd = %w[nethogs -t -C -d 1 -c 10]   

# Exécute la commande et capture : 
# - stdout (dans 'stdout')
# - stderr (dans 'stderr')
# - le statut de processus (Process::Status) dans 'status'.
stdout, stderr, status = Open3.capture3(*cmd)

# Écrit la sortie combinée (stdout + stderr) dans le fichier proc_buffer.
# Écrase ou crée le fichier
File.write("/tmp/proc_buffer", stdout + stderr)

# Fait terminer le script avec le même code de sortie que la commande appelée.
exit status.exitstatus
