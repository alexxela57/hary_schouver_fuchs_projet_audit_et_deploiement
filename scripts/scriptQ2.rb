#!/usr/bin/env ruby
# encoding: UTF-8

#affiche la charge moyenne du cpu
puts `uptime`

#affiche la mémoire et swap disponible et utilisés
puts `free -h | awk '{print $1, $2, $3}'`
