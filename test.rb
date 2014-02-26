#!/usr/bin/env ruby

require 'right_aws'
require 'pp'
require 'yaml'
require './creds.rb'

class Snap
  attr_accessor :id, :time, :status

  def initialize(snap_id)
    @id = snap_id
  end

  def self.from_ec2(snap_hash)
    snap_id = snap_hash[:aws_id]
    if (snap_id.match(/^snap-/)) then
      o = self.new(snap_id)
      if t = snap_hash[:aws_started_at]
        o.time = Time.parse(t)
      end
      if v = snap_hash[:aws_status]
        o.status = v
      end
      o
    else
      nil
    end
  end
end

class Backup

  attr_accessor :id, :lineage, :max_snapshots, :enabled, :snaps
  attr_accessor :minutely, :hourly, :daily, :weekly, :monthly, :yearly
  attr_accessor :minutely_hash, :hourly_hash, :daily_hash, :weekly_hash, :monthly_hash, :yearly_hash
  attr_reader   :now

  def initialize(vol_id)
    @id = vol_id
    @max_snapshots = 10
    @minutely = 0
    @minutely_hash = "%Y%m%d%H%M"
    #@hourly = 60
    @hourly = 55
    @hourly_hash = "%Y%m%d%H"
    @daily = 14
    @daily_hash = "%Y%m%d"
    @weekly = 6
    @weekly_hash = "%G%V"
    @monthly = 12
    @monthly_hash = "%Y%m"
    @yearly = 2
    @yearly_hash = "%Y"
    @snaps = []
    @now = Time.now.utc
  end

  def self.from_ec2(vol_hash)
    #puts "Creating class from:\n #{vol_hash.inspect}"
    vol_id = vol_hash[:aws_id]
    if (vol_id.match(/^vol-/)) then
      o = self.new(vol_id)
      vol_hash[:tags].each do |k,v|
        #puts "HERE: #{k}, #{v}"
        begin
          k.match(/backup:(\w+)/) do |m,n|
            o.send("#{$1}=".to_sym, v)
          end
        rescue
        end
      end
      o
    else
      nil
    end
  end

  def parse_ec2_snaps(snap_array)
     self.snaps = snap_array.collect { |s| Snap.from_ec2(s) }
     self.sort_snaps!
  end

  def snaps_pending
    self.snaps.select { |s| s.status == "pending" }
  end

  def snaps_completed
    self.snaps.select { |s| s.status == "completed" }
  end

  def snaps_error
    self.snaps.select { |s| s.status == "error" }
  end

  def sort_snaps!
    snaps.sort! {|x,y| y.time <=> x.time }
  end

  def schedule_types
    prefix = /^@(\w+)_hash/
    instance_variables.select { |v| v.to_s.match(prefix) }.collect do |v|
      v.to_s.sub(prefix,'\1').to_sym
    end
  end

  def list_snaps(type)
    hash_list = []
    a = self.snaps_completed.select do |s|
      hash = s.time.strftime(self.send("#{type}_hash".to_sym))
      hash_list.index(hash) ? false : hash_list << hash
    end
    a[0..(self.send(type.to_sym))]
  end

  def latest
    self.snaps.find do |s|
      s.status == "completed" || (s.status == "pending" && (self.now - s.time) <= (60*60*4))
    end
  end

  def prune_snaps!
    save_ids = []
    self.schedule_types.each do |sym|
      self.list_snaps(sym).each do |s|
        save_ids << s.id unless save_ids.index(s.id)
      end
    end
    self.snaps.each do |s|
      if s.status != "completed" && (self.now - s.time) <= (60*60*24*14)
        save_ids << s.id unless save_ids.index(s.id)
      end
    end
    to_be_pruned = self.snaps.dup
    to_be_pruned.reject! { |s| save_ids.index(s.id) }
    puts "To be pruned:"
    pp to_be_pruned
    pp to_be_pruned.length
  end

  def snap_required?
    retval = false

    # hash all snaps for each non-zero schedule type, uniq the list,
    #   then check if the current time adds an additional hash to the list
    hash_list = []
    self.snaps.each do |s|
      if s.status == "completed" || (s.status == "pending" && (self.now - s.time) <= (60*60*4))
        self.schedule_types.each do |type|
          hash = s.time.strftime(self.send("#{type}_hash".to_sym))
          hash_list << hash unless hash_list.index(hash)
        end
      end
    end
    self.schedule_types.each do |type|
      next if self.send(type).to_i == 0
      hash = self.now.strftime(self.send("#{type}_hash".to_sym))
      unless hash_list.index(hash)
        #puts "Bingo, need #{type}: #{hash}"
        retval = true
      end
    end
    retval
  end

end

@ec2   = RightAws::Ec2.new(@aws_key,@aws_secret)

vols = []
#vols += @ec2.describe_volumes(:filters => { 'tag-key' => 'backup:enabled' })
#vols += @ec2.describe_volumes(:filters => { 'volume-id' => 'vol-63d1f029' })

vols = YAML.load_file("fixtures/vols.yaml")
vols.each do |v|
  obj = Backup.from_ec2(v)
  obj.parse_ec2_snaps(YAML.load_file("fixtures/snaps.yaml")) 
  obj.prune_snaps!
  pp obj.schedule_types
  pp obj.snaps_pending
  puts "Required:"
  pp obj.snap_required?
end

