#!/usr/bin/env ruby
# encoding: UTF-8
require 'open3'

cmd = %w[nethogs -t -C -d 1 -c 10]   # <- supprimé 'sudo'
stdout, stderr, status = Open3.capture3(*cmd)

File.write("/tmp/proc_buffer", stdout + stderr)

exit status.exitstatus
