#!/usr/bin/env ruby

require 'right_aws'
require 'pp'
require 'yaml'
require './creds.rb'

class Snap
  attr_accessor :id, :time 

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
      o
    else
      nil
    end
  end
end

class Backup

  attr_accessor :id, :lineage, :max_snapshots, :enabled, :snaps
  attr_accessor :minutely, :hourly, :daily, :weekly, :monthly, :yearly
  attr_reader :minutely_hash, :hourly_hash, :daily_hash, :weekly_hash, :monthly_hash, :yearly_hash

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

  def sort_snaps!
    snaps.sort! {|x,y| y.time <=> x.time }
  end

  def list_snaps(type)
    hash_list = []
    a = self.snaps.select do |s|
      hash = s.time.strftime(self.send("#{type}_hash".to_sym))
      hash_list.index(hash) ? false : hash_list << hash
    end
    a[0..(self.send(type.to_sym))]
  end

  def prune_snaps!
    save_ids = []
    [:yearly, :monthly, :weekly, :daily, :hourly, :minutely].each do |sym|
      self.list_snaps(sym).each do |s|
        save_ids << s.id unless save_ids.index(s.id)
      end
    end
    to_be_pruned = self.snaps.dup
    to_be_pruned.reject! { |s| save_ids.index(s.id) }
    puts "To be pruned:"
    pp to_be_pruned
    pp to_be_pruned.length
  end

end

@ec2   = RightAws::Ec2.new(@aws_key,@aws_secret)

# pp @ec2.describe_instances

vols = []
#vols += @ec2.describe_volumes(:filters => { 'tag-key' => 'backup:enabled' })
#vols += @ec2.describe_volumes(:filters => { 'volume-id' => 'vol-63d1f029' })

vols = YAML.load_file("fixtures/vols.yaml")
vols.each do |v|
  obj = Backup.from_ec2(v)
  obj.parse_ec2_snaps(YAML.load_file("fixtures/snaps.yaml")) 
#  puts obj.to_yaml

#  hash_list = []
#  a = obj.snaps.select do |s|
#    #hash = s.time.strftime("%Y")
#    #hash = s.time.strftime("%Y%m")
#    hash = s.time.strftime("%G%V")
#    #hash = s.time.strftime("%Y%m%d")
#    #hash = s.time.strftime("%Y%m%d%H")
#    #hash = s.time.strftime("%Y%m%d%H%M%S")
#    hash_list.index(hash) ? false : hash_list << hash
#  end
#  pp a
#  pp a[0..(obj.weekly)]

#   [:yearly, :monthly, :weekly, :daily, :hourly, :minutely].each do |sym|
#     puts "\nList of #{sym}"
#     pp obj.list_snaps(sym)
#   end
   obj.prune_snaps!
end

