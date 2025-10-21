#!/usr/bin/env ruby
# encoding: UTF-8

require 'json'
require 'stringio'

#buffer pour capturer les puts
buffer = StringIO.new
original_stdout = $stdout
$stdout = buffer

#Q1
puts "1. Affiche le nom, la distribution et la version du noyau \n \n"

`neofetch --stdout`.each_line do |line|
  if line =~ /^\s*\w+@(.+)$/

#affiche le hostname, ce qui se trouve après l'@
    puts $1 
  end
end

#affiche la distribution et la version du noyau 
puts `neofetch --stdout | grep -P 'OS:|^Kernel:'`
puts "---------------------------------------------------------------------------------------------------"

#Q2
puts "2. Affiche la charge moyenne cpu, la mémoire et swap disponible et utilisés \n \n"
#affiche la charge moyenne du cpu
puts `uptime`

#affiche la mémoire et swap disponible et utilisés
puts `free -h | awk '{print $1, $2, $3}'`
puts "---------------------------------------------------------------------------------------------------"

#Q3
puts "3. Liste les interfaces réseau (@mac et @ip) \n \n"
`ip a | grep -E "(link|inet|: )"`.each_line do |line|
    if line =~ /^\d: (.+): </
      puts "nom : #{$1}"
    end
    if line =~ /^\s+link\/[^ ]+ (.+) brd/
      puts "mac : #{$1}"
    end
    if line =~ /^\s+inet ([^\/]+\/\d+)/
      puts "IPv4 : #{$1}"
    end
    if line =~ /^\s+inet6 (.+) scope/
      puts "IPv6 : #{$1}"
    end

end
puts "---------------------------------------------------------------------------------------------------"

#Q4
puts "4. Liste les utilisateurs humain existants, en distinguant ceux actuellement connectés \n \n"
connectes = []
deconnectes = []

`users | grep "$u"`.each_line do |line|
  connectes << line
end
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

#Q5 
puts "5. Affiche l'espace disque par partition, trié par ordre décroissant de la colonne Uti% \n \n"
# Affiche l'espace disque par partition, trié par ordre décroissant de la colonne Uti%
puts "Sys. de fichiers Uti% Taille Utilisé Dispo"
puts `df -h -x tmpfs -x devtmpfs --output=source,pcent,size,used,avail | tail -n +2 | sort -k2 -nr`
puts "---------------------------------------------------------------------------------------------------"

#Q6
puts "6. Affiche les processus les plus consommateurs de CPU et de mémoire \n \n"
puts `ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu | awk '$6 > 0.0 && $7 > 2.0'`
puts "---------------------------------------------------------------------------------------------------"

#Q7
puts "7. Affiche les processus les plus consommateurs de CPU et de mémoire \n \n"
require 'open3'

cmd = %w[nethogs -t -C -d 1 -c 10]   # <- supprime 'sudo'
stdout, stderr, status = Open3.capture3(*cmd)

File.write("/tmp/proc_buffer", stdout + stderr)

exit status.exitstatus
puts "---------------------------------------------------------------------------------------------------"

#Q8
puts "8. Affiche la présence et le status de certains services clés \n \n" 
puts  `systemctl --no-pager --type=service --all | grep -E 'sshd|cron|docker|NetworkManager|systemd-networkd|rsyslog|systemd-journald|firewalld|ufw|nginx|apache2|httpd|mariadb|mysqld|postgresql'`

$stdout = original_stdout

#récupération des lignes qui sont puts
lignes = buffer.string.split("\n")
File.write("resultats.json", JSON.pretty_generate(lignes))
puts lignes

puts "###################################################################################################"
puts "Résultats disponibles dans le fichier .json !"
puts "###################################################################################################"
