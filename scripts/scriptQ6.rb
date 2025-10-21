#!/usr/bin/env ruby
# encoding: UTF-8


puts `ps -eo pid,user,comm,%cpu,%mem --sort=-%cpu | awk '$6 > 0.0 && $7 > 2.0'`
