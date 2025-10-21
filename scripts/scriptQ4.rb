#!/usr/bin/env ruby
# encoding: UTF-8

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
puts "Utilisateur(s) deconnecté(s) : "
puts deconnectes

