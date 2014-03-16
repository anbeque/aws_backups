require 'spec_helper'

describe Backup do
  include RSpec::Mocks::ExampleMethods
  $logger = Logger.new(STDOUT)   if !$logger
  $logger.level = Logger::WARN
  let(:vols) {
    YAML.load_file(File.join(File.dirname(__FILE__),'fixtures','vols.yaml'))
  }
  let(:snaps) {
    YAML.load_file(File.join(File.dirname(__FILE__),'fixtures','snaps.yaml'))
  }
  let(:new_snap) {
    YAML.load_file(File.join(
      File.dirname(__FILE__),'fixtures','pending_snap.yaml'))
  }
  let(:ec2) {
    RightAws::Ec2.new("invalid_key","invalid_secret", :logger => $logger)
  }

  context "with snapshot required" do
    let(:backup) do
      Time.stub(:now).and_return(Time.parse("2014-02-03T10:15:00.000Z"))
      obj = Backup.from_ec2(vols.first, :logger => $logger)
      obj.should_receive(:sort_snaps!).once.and_call_original
      obj.parse_ec2_snaps(snaps)
      obj.api = ec2
      obj
    end

    it "should contain the default config variables" do
      backup.id.should eq("vol-63d1f029")
      backup.api.should_not be_nil
      backup.max_snapshots.to_i.should eq(10)
      backup.minutely.to_i.should      eq(0)
      backup.hourly.to_i.should        eq(60)
      backup.daily.to_i.should         eq(14)
      backup.weekly.to_i.should        eq(6)
      backup.monthly.to_i.should       eq(12)
      backup.yearly.to_i.should        eq(2)
    end

    it "#latest", :checkin => true do
      backup.latest.should respond_to(:time)
      backup.latest.time.to_s.should eq("2014-02-03 09:10:38 UTC")
    end

    it "#schedule_types" do
      backup.schedule_types.should include(:minutely)
      backup.schedule_types.should include(:hourly)
      backup.schedule_types.should include(:daily)
      backup.schedule_types.should include(:weekly)
      backup.schedule_types.should include(:monthly)
      backup.schedule_types.should include(:yearly)
    end

    it "#backup" do
      # Should only ever trigger backup once
      backup.api.should_receive(:create_snapshot).once.with("vol-63d1f029").and_return(new_snap)
      backup.api.should_receive(:create_tags).once.with("snap-12345678", kind_of(Hash))
      backup.backup
      backup.latest.should respond_to(:time)
      backup.latest.time.to_s.should eq("2014-02-03 10:10:40 UTC")
      backup.backup
    end

    it "#prune_snaps!" do
      backup.api.should_receive(:delete_snapshot).once.with("snap-2039a337").and_return(true)
      backup.api.should_receive(:delete_snapshot).once.with("snap-d89803cf").and_return(true)
      backup.api.should_receive(:delete_snapshot).once.with("snap-d4bf21c3").and_return(true)
      backup.api.should_receive(:delete_snapshot).once.with("snap-f3fc63e4").and_return(true)
      backup.hourly = 55
      backup.prune_snaps!
      backup.latest.should respond_to(:time)
      backup.latest.time.to_s.should eq("2014-02-03 09:10:38 UTC")
    end

    it "#snaps_pending" do
      backup.api.should_receive(:create_snapshot).once.with("vol-63d1f029").and_return(new_snap)
      backup.api.should_receive(:create_tags).once.with("snap-12345678", kind_of(Hash))
      backup.backup
      backup.snaps_pending.collect {|s| s.id}.should include("snap-12345678")
      backup.snaps_pending.each do |s|
        s.status.should eq("pending")
      end
    end

    it "#snaps_completed" do
      backup.api.should_receive(:create_snapshot).once.with("vol-63d1f029").and_return(new_snap)
      backup.api.should_receive(:create_tags).once.with("snap-12345678", kind_of(Hash))
      backup.backup
      backup.snaps_pending.collect {|s| s.id}.should include("snap-12345678")
      backup.snaps_completed.collect {|s| s.id}.should_not include("snap-12345678")
      backup.snaps_completed.collect {|s| s.id}.should include("snap-58003a4f")
      backup.snaps_completed.each do |s|
        s.status.should eq("completed")
      end
    end

    it "#snaps_error" do
      backup.api.should_receive(:create_snapshot).once.with("vol-63d1f029").and_return(new_snap)
      backup.api.should_receive(:create_tags).once.with("snap-12345678", kind_of(Hash))
      backup.backup
      backup.snaps_completed.collect {|s| s.id}.should include("snap-58003a4f")
      backup.snaps_error.collect {|s| s.id}.should_not include("snap-58003a4f")
      # TODO: Actually have at least 1 error returned
      # backup.snaps_error.should have_at_least(1).items
      backup.snaps_error.each do |s|
        s.status.should eq("error")
      end
    end

    it "#sort_snaps!" do

      # Shuffle the snaps in a random order
      backup.snaps.shuffle!(random: Random.new(1234))

      # Ensure that at least one snap is NOT in decending time sequence order
      ts = Time.now.utc
      out_of_sequence = backup.snaps.reject { |s| s.time < ts and ts = s.time }
      out_of_sequence.should have_at_least(1).items

      # Sort the snaps, with updated expectation
      backup.should_receive(:sort_snaps!).once.and_call_original
      backup.sort_snaps!

      # Ensure that all snaps are in decending time sequence order
      ts = Time.now.utc
      out_of_sequence = backup.snaps.reject { |s| s.time < ts and ts = s.time }
      out_of_sequence.should have(0).items

    end

    it "#snap_required?" do
      backup.snap_required?.should be_true
      backup.instance_variable_set(:@now,Time.parse("2014-02-03T09:59:00.000Z"))
      backup.snap_required?.should be_false
    end

    it "#list_snaps(:weekly)" do
      snap_list = backup.list_snaps(:weekly).collect { |s| s.time.to_s }
      snap_list.shift.should eq "2014-02-03 09:10:38 UTC"
      snap_list.should have(6).items
      snap_list.should include(
        "2014-02-02 23:10:41 UTC",
        "2014-01-26 23:10:44 UTC",
        "2014-01-19 23:10:44 UTC",
        "2014-01-12 23:10:40 UTC",
        "2014-01-05 23:10:44 UTC",
        "2013-12-29 23:10:52 UTC"
      )
      backup.weekly = "4"
      snap_list = backup.list_snaps(:weekly).collect { |s| s.time.to_s }
      snap_list.should have(5).items
      snap_list.last.should eq "2014-01-12 23:10:40 UTC"
    end

    it "#list_snaps(:monthly)" do
      snap_list = backup.list_snaps(:monthly).collect { |s| s.time.to_s }
      snap_list.shift.should eq "2014-02-03 09:10:38 UTC"
      snap_list.should have(6).items
      snap_list.should include(
        "2014-01-31 23:10:43 UTC",
        "2013-12-31 23:10:41 UTC",
        "2013-11-30 23:10:45 UTC",
        "2013-10-31 23:10:41 UTC",
        "2013-09-30 22:10:36 UTC",
        "2013-08-31 23:10:35 UTC"
      )
    end

    it "#list_snaps(:yearly)" do
      snap_list = backup.list_snaps(:yearly).collect { |s| s.time.to_s }
      snap_list.shift.should eq "2014-02-03 09:10:38 UTC"
      snap_list.should have(1).items
      snap_list.should include(
        "2013-12-31 23:10:41 UTC",
      )
    end

    it "#list_snaps(:minutely)" do
      snap_list = backup.list_snaps(:minutely).collect { |s| s.time.to_s }
      snap_list.shift.should eq "2014-02-03 09:10:38 UTC"
      snap_list.should have(0).items
    end

    it "#list_snaps(:daily)" do
      snap_list = backup.list_snaps(:daily).collect { |s| s.time.to_s }
      snap_list.shift.should eq "2014-02-03 09:10:38 UTC"
      snap_list.should have(14).items
      snap_list.should include(
        "2014-02-02 23:10:41 UTC",
        "2014-02-01 23:10:47 UTC",
        "2014-01-31 23:10:43 UTC",
        "2014-01-30 23:10:43 UTC",
        "2014-01-29 23:10:50 UTC",
        "2014-01-28 23:10:41 UTC",
        "2014-01-27 23:10:52 UTC",
        "2014-01-26 23:10:44 UTC",
        "2014-01-25 23:10:44 UTC",
        "2014-01-24 23:10:42 UTC",
        "2014-01-23 23:10:39 UTC",
        "2014-01-22 23:10:40 UTC",
        "2014-01-21 23:10:42 UTC",
        "2014-01-20 23:10:40 UTC"
      )
    end

    it "#list_snaps(:hourly)" do
      snap_list = backup.list_snaps(:hourly).collect { |s| s.time.to_s }
      snap_list.shift.should eq "2014-02-03 09:10:38 UTC"
      snap_list.should have(60).items
      snap_list.should include(
        "2014-02-03 08:10:44 UTC",
        "2014-02-03 07:10:38 UTC",
        "2014-02-03 06:10:42 UTC",
        "2014-02-03 05:10:39 UTC",
        "2014-02-03 04:10:40 UTC",
        "2014-02-03 03:10:39 UTC",
        "2014-02-03 02:10:42 UTC",
        "2014-02-03 01:10:45 UTC",
        "2014-02-03 00:10:46 UTC",
        "2014-02-02 23:10:41 UTC",
        "2014-02-02 22:10:39 UTC",
        "2014-02-02 21:10:46 UTC",
        "2014-02-02 20:10:39 UTC",
        "2014-02-02 19:10:42 UTC",
        "2014-02-02 18:10:45 UTC",
        "2014-02-02 17:10:44 UTC",
        "2014-02-02 16:10:40 UTC",
        "2014-02-02 15:10:38 UTC",
        "2014-02-02 14:10:45 UTC",
        "2014-02-02 13:10:46 UTC",
        "2014-02-02 12:10:45 UTC",
        "2014-02-02 11:10:39 UTC",
        "2014-02-02 10:10:42 UTC",
        "2014-02-02 09:10:44 UTC",
        "2014-02-02 08:10:43 UTC",
        "2014-02-02 07:10:39 UTC",
        "2014-02-02 06:10:42 UTC",
        "2014-02-02 05:10:41 UTC",
        "2014-02-02 04:10:45 UTC",
        "2014-02-02 03:10:40 UTC",
        "2014-02-02 02:10:40 UTC",
        "2014-02-02 01:10:41 UTC",
        "2014-02-02 00:10:43 UTC",
        "2014-02-01 23:10:47 UTC",
        "2014-02-01 22:10:40 UTC",
        "2014-02-01 21:10:35 UTC",
        "2014-02-01 20:10:54 UTC",
        "2014-02-01 19:10:40 UTC",
        "2014-02-01 18:10:42 UTC",
        "2014-02-01 17:10:43 UTC",
        "2014-02-01 16:10:39 UTC",
        "2014-02-01 15:10:41 UTC",
        "2014-02-01 14:10:39 UTC",
        "2014-02-01 13:10:41 UTC",
        "2014-02-01 12:10:44 UTC",
        "2014-02-01 11:10:41 UTC",
        "2014-02-01 10:10:40 UTC",
        "2014-02-01 09:10:38 UTC",
        "2014-02-01 08:10:43 UTC",
        "2014-02-01 07:10:42 UTC",
        "2014-02-01 06:10:39 UTC",
        "2014-02-01 05:10:54 UTC",
        "2014-02-01 04:10:46 UTC",
        "2014-02-01 03:10:40 UTC",
        "2014-02-01 02:10:40 UTC",
        "2014-02-01 01:10:42 UTC",
        "2014-02-01 00:10:50 UTC",
        "2014-01-31 23:10:43 UTC",
        "2014-01-31 22:10:44 UTC",
        "2014-01-31 21:10:46 UTC"
      )
    end

  end

  context "with backup:enabled = 0" do
    let(:backup) do
      Time.stub(:now).and_return(Time.parse("2014-02-03T10:15:00.000Z"))
      obj = Backup.from_ec2(vols.first, :logger => $logger)
      obj.should_receive(:sort_snaps!).once.and_call_original
      obj.parse_ec2_snaps(snaps)
      obj.api = ec2
      obj.enabled = "0"
      obj
    end

    it "#enabled" do
      [nil, false, "0", "", " ", "FaLse", "nO", "n", "F" ].each do |str|
        backup.enabled = str
        backup.enabled.should be_false
      end
    end

    it "#minutely" do
      [nil, "0", "", " ", "FaLse", "nO", "n", "F" ].each do |str|
        backup.minutely = str
        backup.minutely.should eq(0)
      end
      ["1", "1.234", " 1 " ].each do |str|
        backup.minutely = str
        backup.minutely.should eq(1)
      end
    end

    [:minutely, :hourly, :daily, :weekly, :monthly, :yearly].each do |type|
      it "##{type} should coerce to integer" do
        [nil, "0", "", " ", "FaLse", "nO", "n", "F" ].each do |str|
          backup.send("#{type.to_s}=".to_sym, str)
          backup.send(type).should eq(0), "expected #{str.inspect} to be 0"
        end
        ["1", "1.234", " 1 " ].each do |str|
          backup.send("#{type.to_s}=".to_sym, str)
          backup.send(type).should eq(1), "expected #{str.inspect} to be 1"
        end
      end
    end

    it "#snap_required?" do
      backup.snap_required?.should be_false
    end

    it "#backup should not fire when disabled" do
      backup.api.should_receive(:create_snapshot).exactly(0).times
      backup.api.should_receive(:create_tags).exactly(0).times
      backup.backup
    end

    it "#prune_snaps! should not fire when disabled" do
      backup.api.should_receive(:delete_snapshot).exactly(0).times
      backup.hourly = 55
      backup.prune_snaps!
    end

    it "#generate_snap_tags" do
      #Time.stub(:now).and_return(Time.parse("2014-02-03T10:15:00.000Z"))
      tags = backup.generate_snap_tags
      tags.should include( "backup:lineage"     => "releng-jenkins-master-1")
      tags.should include( "backup:device"      => "/dev/sdf")
      tags.should include( "backup:position"    => "1")
      tags.should include( "backup:volume_name" => "JENKINS HOME")
      tags.should include( "backup:stripe_id"   => "20140203101500")
      tags.should include( "backup:timestamp"   => "1391422500")
      tags.should include( "backup:worker" )
      tags.should include( "backup:worker_pid" )
    end

  end
end
