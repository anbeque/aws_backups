#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'right_aws'
require 'logger'
require_relative '../lib/creds'
require_relative '../lib/backup'

@logger = Logger.new(STDOUT)   if !@logger
@ec2   = RightAws::Ec2.new(@aws_key,@aws_secret, :logger => @logger)

vols = @ec2.describe_volumes(:filters => { 'tag:backup:enabled' => '1' })

vols.each do |v|
  obj = Backup.from_ec2(v, :logger => @logger)
  obj.api = @ec2
  obj.parse_ec2_snaps(@ec2.describe_snapshots(:filters => { 'volume-id' => obj.id }))
  obj.api = nil
  obj.backup
  obj.prune_snaps!
end

