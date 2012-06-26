#!/usr/bin/env ruby -wKU

require "benchmark"
require "thread_safe"

hash  = {}
cache = ThreadSafe::Cache.new

10_000.times do |i|
  hash[i]  = i
  cache[i] = i
end

TESTS = 40_000_000
Benchmark.bmbm do |results|
  key = rand(10_000)

  results.report('Hash#[]') do
    TESTS.times { hash[key] }
  end

  results.report('Cache#[]') do
    TESTS.times { cache[key] }
  end
end