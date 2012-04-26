#!/usr/bin/env rake
require "bundler/gem_tasks"
require 'rake/testtask'

task :default => :test

Rake::TestTask.new :test do |t|
  t.libs << "lib"
  t.test_files = FileList["test/**/*.rb"]
end
