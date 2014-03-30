#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'right_aws'
require 'logger'
require 'open-uri'
require 'json'
require_relative '../lib/backup'

@logger = Logger.new(STDOUT)   if !@logger

def query_role
  r = open("http://169.254.169.254/latest/meta-data/iam/security-credentials/").readlines.first
  r
end

def query_role_credentials(role = query_role)
  fail "Instance has no IAM role." if role.to_s.empty?
  creds = open("http://169.254.169.254/latest/meta-data/iam/security-credentials/#{role}"){|f| JSON.parse(f.string)}
  @logger.debug("Retrieved instance credentials for IAM role #{role}")
  creds
end

if @aws_key and @aws_secret
  @ec2 = RightAws::Ec2.new(@aws_key,@aws_secret, :logger => @logger)
else
  creds = query_role_credentials
  @ec2 =  RightAws::Ec2.new(creds['AccessKeyId'], creds['SecretAccessKey'], {:logger => @logger, :token => creds['Token']})
end

vols = @ec2.describe_volumes(:filters => { 'tag:backup:enabled' => '1' })

vols.each do |v|
  obj = Backup.from_ec2(v, :logger => @logger)
  obj.api = @ec2
  obj.parse_ec2_snaps(@ec2.describe_snapshots(:filters => { 'volume-id' => obj.id }))
  obj.backup
  obj.prune_snaps!
end

