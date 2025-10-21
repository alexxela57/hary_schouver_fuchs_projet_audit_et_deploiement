#!/usr/bin/env ruby
# encoding: UTF-8

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

