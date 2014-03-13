require 'spec_helper'

describe Backup do
  context "New backup required" do
    include RSpec::Mocks::ExampleMethods
    $logger = Logger.new(STDOUT)   if !$logger
    $logger.level = Logger::WARN
    let(:vols)  { YAML.load_file("./fixtures/vols.yaml") }
    let(:snaps) { YAML.load_file("./fixtures/snaps.yaml") }
    let(:new_snap) { YAML.load_file("./fixtures/pending_snap.yaml") }
    let(:ec2) { RightAws::Ec2.new("invalid_key","invalid_secret", :logger => $logger) }
    let(:backup) do
      Time.stub(:now).and_return(Time.parse("2014-02-03T10:15:00.000Z"))
      obj = Backup.from_ec2(vols.first, :logger => $logger)
      obj.parse_ec2_snaps(snaps)
      obj.api = ec2
      obj
    end

    it "#latest", :checkin => true do
      backup.latest.should respond_to(:time)
      backup.latest.time.to_s.should eq("2014-02-03 09:10:38 UTC")
    end

    it "should contain the standard backup variables" do
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

    it "#backup" do
      # Should only ever trigger backup once
      ec2.should_receive(:create_snapshot).once.with("vol-63d1f029").and_return(new_snap)
      backup.backup
      backup.latest.should respond_to(:time)
      backup.latest.time.to_s.should eq("2014-02-03 10:10:40 UTC")
      backup.backup
    end

    it "#prune_snaps!" do
      ec2.should_receive(:delete_snapshot).once.with("snap-2039a337").and_return(true)
      ec2.should_receive(:delete_snapshot).once.with("snap-d89803cf").and_return(true)
      ec2.should_receive(:delete_snapshot).once.with("snap-d4bf21c3").and_return(true)
      ec2.should_receive(:delete_snapshot).once.with("snap-f3fc63e4").and_return(true)
      backup.hourly = 55
      backup.prune_snaps!
      backup.latest.should respond_to(:time)
      backup.latest.time.to_s.should eq("2014-02-03 09:10:38 UTC")
    end

  end
end
