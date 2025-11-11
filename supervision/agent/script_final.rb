#!/usr/bin/env ruby
# encoding: UTF-8

require 'json'
require 'stringio'
require 'set'

#----------- Formatage partitions ---------
SKIP_FS = %w[
  tmpfs
  devtmpfs
  overlay
  squashfs
  proc
  sysfs
  cgroup
  cgroup2
  mqueue
  hugetlbfs
  devpts
  bpf
  pstore
  tracefs
  securityfs
  debugfs
  configfs
  nsfs
  efivarfs
  fusectl
].freeze

SKIP_MOUNT_PREFIXES = %w[
  /proc
  /sys
  /run/docker/netns
  /dev/pts
  /dev/mqueue
  /dev/hugepages
].freeze

# ---------- Utils ----------
def run(cmd)
  `#{cmd}`.strip
rescue
  ""
end

HOST = "/host"

def safe_read(path)
  File.read(path)
rescue
  nil
end

def meta
  # hostname du host
  hostname = safe_read("#{HOST}/etc/hostname")&.strip
  if hostname.nil? || hostname.empty?
    hostname = run("chroot #{HOST} hostname")
  end
  hostname = "unknown" if hostname.nil? || hostname.empty?

  # OS du host
  os_release = safe_read("#{HOST}/etc/os-release")
  os_name = if os_release
  os_release[/^PRETTY_NAME="([^"]+)"/, 1] ||
              os_release[/^NAME="([^"]+)"/, 1]
end
os_name ||= "unknown"

# noyau du host
kernel = run("chroot #{HOST} uname -r")
kernel = "unknown" if kernel.nil? || kernel.empty?

{
  hostname: hostname,
  os:       os_name,
  kernel:   kernel,
  ts:       Time.now.strftime("%Y-%m-%d_%H:%M:%S")
}
end


# ---------- Services -------------

SERVICE_CANDIDATES = {
  "sshd"               => %w[sshd],
  "cron"               => %w[crond cron],
  "dockerd"            => %w[dockerd],
  "NetworkManager"     => %w[NetworkManager],
  "systemd-networkd"   => %w[systemd-networkd networkd],
  "rsyslog"            => %w[rsyslogd],
  "systemd-journald"   => %w[systemd-journal systemd-journald],
  "ufw"                => %w[ufw],
  "nginx"              => %w[nginx],
  "apache2"            => %w[apache2 httpd],
  "httpd"              => %w[httpd apache2],
  "mariadb"            => %w[mariadbd mariadb mysqld],
  "postgres"           => %w[postgres]
}

def host_process_index
  comms = Set.new
  cmdls = []
  Dir.glob("/host/proc/[0-9]*/comm").each  { |f| comms << File.read(f, mode: 'rb').to_s.strip rescue nil }
  Dir.glob("/host/proc/[0-9]*/cmdline").each do |f|
    s = (File.read(f, mode: 'rb').to_s.tr("\0", ' ').strip rescue nil)
    cmdls << s if s && !s.empty?
  end
  [comms, cmdls]
end

def read_services_map(candidates)
  comms, cmdls = host_process_index
  candidates.map do |label, names|
    up = names.any? do |n|
      comms.include?(n) || cmdls.any? { |c| c =~ /(^|\/)#{Regexp.escape(n)}(\s|$)/ }
    end

    if !up && label == "systemd-journald" && File.socket?("/host/run/systemd/journal/socket")
      up = true
    end
    { name: label, up: up ? 1 : 0 }
  end
end


# ---------- Métriques host ----------
def read_load
  l1,l5,l15 = File.read("#{HOST}/proc/loadavg").split[0,3].map!(&:to_f)
  { load1: l1, load5: l5, load15: l15 }
end

def read_mem
  info = {}
  File.readlines("#{HOST}/proc/meminfo").each do |l|
    k,v = l.split(':',2); info[k] = v.to_s.strip.split.first.to_i * 1024
  end
  total = info['MemTotal']||0
  avail = info['MemAvailable']||(info['MemFree']||0)
  swap_t = info['SwapTotal']||0
  swap_f = info['SwapFree'] ||0
  { total_bytes: total, used_bytes: [total-avail,0].max,
    swap_total_bytes: swap_t, swap_used_bytes: [swap_t-swap_f,0].max }
end

def read_cpu_times
  data = safe_read("#{HOST}/proc/stat")
  return nil unless data

  line = data.lines.find { |l| l.start_with?("cpu ") }
  return nil unless line

  fields = line.split
  # fields: cpu user nice system idle iowait irq softirq steal guest guest_nice
  user    = fields[1].to_i
  nice    = fields[2].to_i
  system  = fields[3].to_i
  idle    = fields[4].to_i
  iowait  = fields[5].to_i rescue 0
  irq     = fields[6].to_i rescue 0
  softirq = fields[7].to_i rescue 0
  steal   = fields[8].to_i rescue 0

  idle_all  = idle + iowait
  non_idle  = user + nice + system + irq + softirq + steal
  total     = idle_all + non_idle

  { idle: idle_all, total: total }
end

def read_cpu_usage_percent(interval = 0.5)
  t1 = read_cpu_times
  return nil unless t1

  sleep interval

  t2 = read_cpu_times
  return nil unless t2

  idle_delta  = t2[:idle]  - t1[:idle]
  total_delta = t2[:total] - t1[:total]

  return nil if total_delta <= 0

  usage = 1.0 - idle_delta.to_f / total_delta.to_f
  (usage * 100.0).round(2)   # pourcentage sur 0–100 avec 2 décimales
end

def read_cpu
  usage = read_cpu_usage_percent(0.5)
  usage ||= 0.0
  { usage_percent: usage }
end



def read_disks
  mounts_content = safe_read("#{HOST}/proc/1/mounts")
  unless mounts_content
    mounts_content = run("chroot #{HOST} cat /proc/1/mounts")
  end
  return [] unless mounts_content

  disks = []

  mounts_content.each_line do |line|
    dev, mountpoint, fstype, *_ = line.split

    # 1) filtrage par type de FS
    next if SKIP_FS.include?(fstype)

    # 2) filtrage par chemin (pseudo FS, namespaces, etc.)
    next if SKIP_MOUNT_PREFIXES.any? { |p| mountpoint.start_with?(p) }

    host_mount = "#{HOST}#{mountpoint}"
    next unless File.directory?(host_mount)

    df_output = run("df -B1 --output=target,size,used \"#{host_mount}\" | tail -n +2")
    next unless df_output

    _, size_str, used_str = df_output.split

    disks << {
      mount:       mountpoint,
      device:      dev,
      total_bytes: size_str.to_i,
      used_bytes:  used_str.to_i
    }
  end

  disks
end




# ---------- Construction JSON ----------
ENV['TZ'] = 'Europe/Paris'
ts = Time.now.strftime("%Y-%m-%d_%H:%M:%S")

result = {
  metrics: {
            meta:     meta,
            cpu:      read_cpu,                       # <-- ajout
            load:     read_load,
            mem:      read_mem,
            disk:     read_disks,
            services: read_services_map(SERVICE_CANDIDATES)
            }
  }



File.write("/app/audit.json", JSON.pretty_generate(result))
puts "JSON écrit: /app/audit.json"
