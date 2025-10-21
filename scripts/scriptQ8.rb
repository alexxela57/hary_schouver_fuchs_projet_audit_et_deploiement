#!/usr/bin/env ruby
# encoding: UTF-8


puts  `systemctl --no-pager --type=service --all | grep -E 'sshd|cron|docker|NetworkManager|systemd-networkd|rsyslog|systemd-journald|firewalld|ufw|nginx|apache2|httpd|mariadb|mysqld|postgresql'`
