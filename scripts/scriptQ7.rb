#!/usr/bin/env ruby
# encoding: UTF-8
require 'open3'

cmd = %w[sudo nethogs -t -C -d 1 -c 10]
stdout, stderr, status = Open3.capture3(*cmd)

File.write("#{ARGV[0]}", stdout + stderr)

exit status.exitstatus


