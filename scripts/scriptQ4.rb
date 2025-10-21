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

puts "connectés : "
puts connectes
puts "deconnectés : "
puts deconnectes

