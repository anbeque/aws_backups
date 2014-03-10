require 'rubygems'
require 'bundler/setup'
require 'rspec/core/rake_task'
require 'yaml'

RSpec::Core::RakeTask.new(:test, :tag) do |t, task_args|
  t.rspec_opts = []
  t.rspec_opts << "--format d"
  # t.rspec_opts << "--backtrace"
  unless task_args[:tag].nil?
    t.rspec_opts << "--tag #{task_args[:tag]}"
  end
end

task :default => :test
task :spec => :test
