#!/usr/bin/env ruby
# encoding: UTF-8

require 'json'
require 'stringio'
require 'set'

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

def read_disks
  # 1) Try to get the host's mounts list
  mounts_txt = nil

  # Prefer host's /proc/1/mounts (may be blocked by hidepid/userns)
  begin
    mounts_txt = File.read("/host/proc/1/mounts")
  rescue
    mounts_txt = nil
  end

  # Fallback: read via chroot (stays in our ns but reads host /proc contents)
  if mounts_txt.nil? || mounts_txt.strip.empty?
    mounts_txt = `chroot /host /bin/sh -c 'cat /proc/1/mounts 2>/dev/null'`
  end

  return [] if mounts_txt.nil? || mounts_txt.strip.empty?

  # 2) Parse & filter mounts (skip tmpfs/devtmpfs/overlay/squashfs etc.)
  skip_fs = %w[tmpfs devtmpfs overlay squashfs]
  mps = mounts_txt.lines.map do |ln|
    parts = ln.split(" ")
    next nil unless parts.size >= 3
    mp  = parts[1]
    fst = parts[2]
    next nil if skip_fs.include?(fst)
    mp
  end.compact.uniq

  # 3) For each mountpoint, run df against the *host* path (/host + mp)
  result = []
  mps.each do |mp|
    host_path = "/host#{mp}"
    # Use df in bytes, parse one line of output
    out = `df -B1 --output=target,size,used "#{host_path}" 2>/dev/null`.lines rescue []
    next if out.nil? || out.size < 2
    tgt, size, used = out[1].strip.split(/\s+/, 3)
    next unless tgt && size && used
    result << {
      mount: mp.gsub(/["\\]/, ''),
      total_bytes: size.to_i,
      used_bytes:  used.to_i
    }
  end

  result
end



# ---------- Construction JSON ----------
ENV['TZ'] = 'Europe/Paris'
ts = Time.now.strftime("%Y-%m-%d_%H:%M:%S")

result = {
  metrics: {
            meta:     meta,
            load:     read_load,
            mem:      read_mem,
            disk:     read_disks,
            services: read_services_map(SERVICE_CANDIDATES)
           }
}


File.write("/app/audit.json", JSON.pretty_generate(result))
puts "JSON écrit: /app/audit.json"
