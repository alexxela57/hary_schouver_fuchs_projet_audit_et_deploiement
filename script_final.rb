#!/usr/bin/env ruby
# encoding: UTF-8

require 'json'
require 'stringio'

#######################################
# Capture des sorties 'puts' dans un buffer
#######################################
buffer = StringIO.new
original_stdout = $stdout
$stdout = buffer

#######################################
# Q1 : Affiche le nom, la distribution et la version du noyau
#######################################
puts "1. Affiche le nom, la distribution et la version du noyau \n\n"

# Extraction du hostname (après @)
`neofetch --stdout`.each_line do |line|
  if line =~ /^\s*\w+@(.+)$/
    puts $1  # hostname
  end
end

# Affiche la distribution et la version du noyau
puts `neofetch --stdout | grep -P 'OS:|^Kernel:'`
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q2 : Charge CPU + mémoire / swap utilisés et disponibles
#######################################
puts "2. Affiche la charge moyenne cpu, la mémoire et swap disponible et utilisés \n\n"

# Charge moyenne CPU
puts `uptime`

# Mémoire et swap (total / utilisé)
puts `free -h | awk '{print $1, $2, $3}'`
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q3 : Liste des interfaces réseau (MAC + IP)
#######################################
puts "3. Liste les interfaces réseau (@mac et @ip) \n\n"

`ip a | grep -E "(link|inet|: )"`.each_line do |line|
  if line =~ /^\d: (.+): </
    puts "nom : #{$1}"  # Nom de l'interface
  end
  if line =~ /^\s+link\/[^ ]+ (.+) brd/
    puts "mac : #{$1}"  # Adresse MAC
  end
  if line =~ /^\s+inet ([^\/]+\/\d+)/
    puts "IPv4 : #{$1}" # Adresse IPv4
  end
  if line =~ /^\s+inet6 (.+) scope/
    puts "IPv6 : #{$1}" # Adresse IPv6
  end
end
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q4 : Liste des utilisateurs humains + qui est connecté
#######################################
puts "4. Liste les utilisateurs humain existants, en distinguant ceux actuellement connectés \n\n"

connectes = []
deconnectes = []

# Récupère les utilisateurs actuellement connectés
`users | grep "$u"`.each_line do |line|
  connectes << line
end

# Liste des utilisateurs avec UID >= 1000 (utilisateurs humains)
`grep -E '^[^:]*:[^:]*:[1-9][0-9]{3,}:' /etc/passwd | cut -d: -f1`.each_line do |line|
  if !connectes.include?(line)
    deconnectes << line
  end
end

puts "Utilisateur(s) connecté(s) : "
puts connectes
puts " "
puts "Utilisateur(s) déconnecté(s) : "
puts deconnectes
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q5 : Espace disque par partition (trié par Uti%)
#######################################
puts "5. Affiche l'espace disque par partition, trié par ordre décroissant de la colonne Uti% \n\n"

puts "Sys. de fichiers Uti% Taille Utilisé Dispo"
puts `df -h -x tmpfs -x devtmpfs --output=source,pcent,size,used,avail | tail -n +2 | sort -k2 -nr`
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q6 : Processus les plus gourmands CPU + mémoire
#######################################
puts "6. Affiche les processus les plus consommateurs de CPU et de mémoire \n\n"

puts `ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu | awk '$6 > 0.0 && $7 > 2.0'`
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q7 : Placeholder 
#######################################
puts "7. Affiche les processus les plus consommateurs de CPU et de mémoire \n\n"

# Code commenté - nethogs (nécessite sudo et interactions)
# require 'open3'
# cmd = %w[nethogs -t -C -d 1 -c 10]
# stdout, stderr, status = Open3.capture3(*cmd)
# File.write("/tmp/proc_buffer", stdout + stderr)
# exit status.exitstatus

puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q8 : Statut de services système clés
#######################################
puts "8. Affiche la présence et le status de certains services clés \n\n"

puts `systemctl --no-pager --type=service --all | grep -E 'sshd|cron|docker|NetworkManager|systemd-networkd|rsyslog|systemd-journald|firewalld|ufw|nginx|apache2|httpd|mariadb|mysqld|postgresql'`

puts "---------------------------------------------------------------------------------------------------"

#######################################
# Sauvegarde des résultats dans un fichier JSON
#######################################
$stdout = original_stdout  # Restauration de la sortie standard

# Extraction des lignes capturées
lignes = buffer.string.split("\n")

# Écriture dans un fichier JSON
File.write("./resultats.json", JSON.pretty_generate(lignes))

# Affichage du contenu dans le terminal
puts lignes

puts "###################################################################################################"
puts "Résultats disponibles dans le fichier .json !"
puts "###################################################################################################"

