#!/usr/bin/env ruby
# encoding: UTF-8


puts `df -h -x tmpfs -x devtmpfs --output=source,size,used,avail,pcent`
