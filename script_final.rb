#!/usr/bin/env ruby
# encoding: UTF-8

require 'json'
require 'stringio'


#######################################
# Buffer pour capturer les puts
#######################################
buffer = StringIO.new
original_stdout = $stdout
$stdout = buffer

#######################################
# Q1 - Affiche nom, distribution et version noyau
#######################################
puts "1. Affiche le nom, la distribution et la version du noyau \n \n"

`neofetch --stdout`.each_line do |line|
  if line =~ /^\s*\w+@(.+)$/
    # Affiche le hostname (ce qui est après le @)
    puts $1 
  end
end

# Affiche la distribution et la version du noyau 
puts `neofetch --stdout | grep -P 'OS:|^Kernel:'`
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q2 - Charge CPU + mémoire et swap
#######################################
puts "2. Affiche la charge moyenne cpu, la mémoire et swap disponible et utilisés \n \n"

# Charge moyenne CPU
puts `uptime`

# Mémoire et swap disponibles et utilisés
puts `free -h | awk '{print $1, $2, $3}'`
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q3 - Interfaces réseau (nom, MAC, IP)
#######################################
puts "3. Liste les interfaces réseau (@mac et @ip) \n \n"

`ip a | grep -E "(link|inet|: )"`.each_line do |line|
    if line =~ /^\d: (.+): </
      # Nom de l'interface
      puts "nom : #{$1}"
    end
    if line =~ /^\s+link\/[^ ]+ (.+) brd/
      # Adresse MAC
      puts "mac : #{$1}"
    end
    if line =~ /^\s+inet ([^\/]+\/\d+)/
      # Adresse IPv4
      puts "IPv4 : #{$1}"
    end
    if line =~ /^\s+inet6 (.+) scope/
      # Adresse IPv6
      puts "IPv6 : #{$1}"
    end
end
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q4 - Utilisateurs humains connectés / déconnectés
#######################################
puts "4. Liste les utilisateurs humain existants, en distinguant ceux actuellement connectés \n \n"

connectes = []
deconnectes = []

# Récupère les utilisateurs actuellement connectés
`users | grep "$u"`.each_line do |line|
  connectes << line
end

# Liste les utilisateurs humains (UID >= 1000)
`grep -E '^[^:]*:[^:]*:[1-9][0-9]{3,}:' /etc/passwd | cut -d: -f1 `.each_line do |line|
  if !connectes.include?(line)
    deconnectes << line
  end
end

puts "Utilisateur(s) connecté(s) : "
puts connectes
puts " "
puts "Utilisateur(s) deconnecté(s) : "
puts deconnectes
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q5 - Espace disque par partition (trié Uti%)
#######################################
puts "5. Affiche l'espace disque par partition, trié par ordre décroissant de la colonne Uti% \n \n"

# Affiche l'espace disque (trié par % utilisation)
puts "Sys. de fichiers Uti% Taille Utilisé Dispo"
puts `df -h -x tmpfs -x devtmpfs --output=source,pcent,size,used,avail | tail -n +2 | sort -k2 -nr`
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q6 - Processus les plus gourmands CPU/Mémoire
#######################################
puts "6. Affiche les processus les plus consommateurs de CPU et de mémoire \n \n"

puts `ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu | awk '$6 > 0.0 && $7 > 2.0'`
puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q7 - (Désactivé) Processus réseau via nethogs
#######################################
puts "7. Processus les plus gourmands en trafic réseau \n \n"

require 'open3' 

# tableau sans interpolation 
cmd = %w[nethogs -t -C -d 1 -c 10]   
# supprimer 'sudo' et capture la stdout et nethogs
# '*' est l'opérateur de décomposition, qui permet d'écrire la commande en un tableau entier
stdout, stderr, status = Open3.capture3(*cmd) 
puts stdout + stderr


puts "---------------------------------------------------------------------------------------------------"

#######################################
# Q8 - Vérifie présence et status de services clés
#######################################
puts "8. Affiche la présence et le status de certains services clés \n \n" 




process_names = %w[
  sshd cron dockerd NetworkManager systemd-networkd
  rsyslog systemd-journald firewalld ufw
  nginx apache2 httpd mariadbd mariadb mysqld postgres
]

process_names.each do |name|
  # pgrep cherche un processus par son nom | >/dev/null redirige stdout stderr vers void 
  up = system("pgrep -x #{name} >/dev/null 2>&1") 
  # 18 emplacements par rapport au nombre de services
  printf("%-18s %s\n", name, up ? "up" : "down")
end


#######################################
# Sauvegarde des résultats dans un fichier JSON avec horodatage
#######################################
$stdout = original_stdout

# Récupération des lignes qui sont puts
lignes = buffer.string.split("\n")

# Ajout d’un horodatage ISO 8601
ENV['TZ'] = 'Europe/Paris'
horodatage = Time.now.strftime("%Y-%m-%d_%H:%M:%S")

# Construction de la structure JSON avec horodatage
resultat = {
  horodatage: horodatage,
  lignes: lignes
}

# Nom du fichier avec horodatage (ex: resultats_2025-10-22T15-30-00.json)
fichier_nom = "resultats_#{Time.now.strftime("%Y-%m-%d_%H:%M:%S")}.json"
File.write(fichier_nom, JSON.pretty_generate(resultat))

puts lignes
puts "###################################################################################################"
puts "Résultats disponibles dans le fichier JSON : #{fichier_nom}"
puts "###################################################################################################"
