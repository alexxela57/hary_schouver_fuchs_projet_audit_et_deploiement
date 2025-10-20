#!/usr/bin/env ruby
# encoding: UTF-8


`neofetch --stdout`.each_line do |line|
  if line =~ /^\s*\w+@(.+)$/

#affiche le hostname, ce qui se trouve après l'@
    puts $1 
  end
end

#affiche la distribution et la version du noyau 
puts `neofetch --stdout | grep -P 'OS:|^Kernel:'`
