require 'test/unit'
require 'thread_safe'
require 'thread'
require File.join(File.dirname(__FILE__), "test_helper")

Thread.abort_on_exception = true

class TestCache < Test::Unit::TestCase
  def setup
    @cache = ThreadSafe::Cache.new
  end

  def test_concurrency
    cache = @cache
    assert_nothing_raised do
      (1..100).map do |i|
        Thread.new do
          1000.times do |j|
            key = i*1000+j
            cache[key] = i
            cache[key]
            cache.delete(key)
          end
        end
      end.map(&:join)
    end
  end

  def test_retrieval
    assert_equal nil, @cache[:a]
    @cache[:a] = 1
    assert_equal 1,   @cache[:a]
  end

  def test_put_if_absent
    assert_equal nil, @cache.put_if_absent(:a, 1)
    assert_equal 1,   @cache.put_if_absent(:a, 1)
    assert_equal 1,   @cache.put_if_absent(:a, 2)
    assert_equal 1,   @cache[:a]
  end

  def test_put_if_absent_with_default_proc
    @cache = ThreadSafe::Cache.new {|h, k| h[k] = 2}
    assert_equal nil, @cache.put_if_absent(:a, 1)
    assert_equal 1,   @cache.put_if_absent(:a, 1)
    assert_equal 1,   @cache.put_if_absent(:a, 2)
    assert_equal 1,   @cache[:a]
  end

  def test_compute_if_absent
    assert_equal(1,   (@cache.compute_if_absent(:a) {1}))
    assert_equal(1,   (@cache.compute_if_absent(:a) {2}))
    assert_equal 1,    @cache[:a]
    @cache[:b] = nil
    assert_equal(nil, (@cache.compute_if_absent(:b) {1}))
  end

  def test_compute_if_absent_with_default_proc
    @cache = ThreadSafe::Cache.new {|h, k| h[k] = 1}
    assert_equal(2,   (@cache.compute_if_absent(:a) {2}))
    assert_equal 2,    @cache[:a]
    assert_equal(nil, (@cache.compute_if_absent(:b) {}))
    assert_equal nil,  @cache[:b]
    assert_equal true, @cache.key?(:b)
  end

  def test_compute_if_absent_exception
    exception_klass = Class.new(Exception)
    assert_raise(exception_klass) do
      @cache.compute_if_absent(:a) { raise exception_klass, '' }
    end
    assert_equal false, @cache.key?(:a)
  end

  def test_compute_if_absent_atomicity
    late_compute_threads_count       = 10
    late_put_if_absent_threads_count = 10
    getter_threads_count             = 5
    compute_started = ThreadSafe::Test::Latch.new(1)
    compute_proceed = ThreadSafe::Test::Latch.new(late_compute_threads_count + late_put_if_absent_threads_count + getter_threads_count)
    block_until_compute_started = lambda do |name|
      if (v = @cache[:a]) != nil
        assert_equal nil, v
      end
      compute_proceed.release
      compute_started.await
    end

    late_compute_threads = Array.new(late_compute_threads_count) do
      Thread.new do
        block_until_compute_started.call('compute_if_absent')
        assert_equal(1, (@cache.compute_if_absent(:a) { flunk }))
      end
    end

    late_put_if_absent_threads = Array.new(late_put_if_absent_threads_count) do
      Thread.new do
        block_until_compute_started.call('put_if_absent')
        assert_equal(1, @cache.put_if_absent(:a, 2))
      end
    end

    getter_threads = Array.new(getter_threads_count) do
      Thread.new do
        block_until_compute_started.call('getter')
        Thread.pass while @cache[:a].nil?
        assert_equal 1, @cache[:a]
      end
    end

    Thread.new do
      @cache.compute_if_absent(:a) do
        compute_started.release
        compute_proceed.await
        sleep(0.2)
        1
      end
    end.join
    (late_compute_threads + late_put_if_absent_threads + getter_threads).each(&:join)
  end

  def test_replace_pair
    assert_equal false, @cache.replace_pair(:a, 1, 2)
    @cache[:a] = 1
    assert_equal true,  @cache.replace_pair(:a, 1, 2)
    assert_equal false, @cache.replace_pair(:a, 1, 2)
    assert_equal 2,     @cache[:a]
    assert_equal true,  @cache.replace_pair(:a, 2, 2)
    assert_equal 2,     @cache[:a]
    assert_equal true,  @cache.replace_pair(:a, 2, nil)
    assert_equal false, @cache.replace_pair(:a, 2, nil)
    assert_equal nil,   @cache[:a]
    assert_equal true,  @cache.key?(:a)
    assert_equal true,  @cache.replace_pair(:a, nil, nil)
    assert_equal true,  @cache.key?(:a)
    assert_equal true,  @cache.replace_pair(:a, nil, 1)
    assert_equal 1,     @cache[:a]
  end

  def test_replace_if_exists
    assert_equal nil,   @cache.replace_if_exists(:a, 1)
    assert_equal false, @cache.key?(:a)
    @cache[:a] = 1
    assert_equal 1,     @cache.replace_if_exists(:a, 2)
    assert_equal 2,     @cache[:a]
    assert_equal 2,     @cache.replace_if_exists(:a, nil)
    assert_equal nil,   @cache[:a]
    assert_equal nil,   @cache.replace_if_exists(:a, 1)
    assert_equal 1,     @cache[:a]
  end

  def test_replace_if_exists_with_default_proc
    @cache = ThreadSafe::Cache.new {|h, k| h[k] = 2}
    assert_equal nil,   @cache.replace_if_exists(:a, 1)
    assert_equal false, @cache.key?(:a)
  end

  def test_key
    assert_equal false, @cache.key?(:a)
    @cache[:a] = 1
    assert_equal true,  @cache.key?(:a)
  end

  def test_delete
    assert_equal nil,   @cache.delete(:a)
    @cache[:a] = 1
    assert_equal 1,     @cache.delete(:a)
    assert_equal nil,   @cache[:a]
    assert_equal false, @cache.key?(:a)
    assert_equal nil,   @cache.delete(:a)
  end

  def test_delete_pair
    assert_equal false, @cache.delete_pair(:a, 2)
    @cache[:a] = 1
    assert_equal false, @cache.delete_pair(:a, 2)
    assert_equal 1,     @cache[:a]
    assert_equal true,  @cache.delete_pair(:a, 1)
    assert_equal false, @cache.delete_pair(:a, 1)
    assert_equal false, @cache.key?(:a)
  end

  def test_default_proc
    cache = ThreadSafe::Cache.new {|h,k| h[k] = 1}
    assert_equal false, cache.key?(:a)
    assert_equal 1,     cache[:a]
    assert_equal true,  cache.key?(:a)
  end

  def test_falsy_default_proc
    cache = ThreadSafe::Cache.new {|h,k| h[k] = nil}
    assert_equal false, cache.key?(:a)
    assert_equal nil,   cache[:a]
    assert_equal true,  cache.key?(:a)
  end

  def test_fetch
    assert_equal nil,   @cache.fetch(:a)
    assert_equal false, @cache.key?(:a)

    assert_equal(1, (@cache.fetch(:a) {1}))

    assert_equal true, @cache.key?(:a)
    assert_equal 1,    @cache[:a]
    assert_equal 1,    @cache.fetch(:a)

    assert_equal(1, (@cache.fetch(:a) {flunk}))
  end

  def test_falsy_fetch
    assert_equal false, @cache.key?(:a)

    assert_equal(nil, (@cache.fetch(:a) {}))

    assert_equal true, @cache.key?(:a)
    assert_equal(nil, (@cache.fetch(:a) {flunk}))
  end

  def test_fetch_with_return
    r = lambda do
      @cache.fetch(:a) { return 10 }
    end.call

    assert_equal 10,    r
    assert_equal false, @cache.key?(:a)
  end

  def test_clear
    @cache[:a] = 1
    assert_equal @cache, @cache.clear
    assert_equal false,  @cache.key?(:a)
    assert_equal nil,    @cache[:a]
  end

  def test_each_pair
    @cache.each_pair {|k, v| flunk}
    assert_equal(@cache, (@cache.each_pair {}))
    @cache[:a] = 1

    h = {}
    @cache.each_pair {|k, v| h[k] = v}
    assert_equal({:a => 1}, h)

    @cache[:b] = 2
    h = {}
    @cache.each_pair {|k, v| h[k] = v}
    assert_equal({:a => 1, :b => 2}, h)
  end

  def test_each_pair_iterator
    @cache[:a] = 1
    @cache[:b] = 2
    i = 0
    r = @cache.each_pair do |k, v|
      if i == 0
        i += 1
        next
        flunk
      elsif i == 1
        break :breaked
      end
    end

    assert_equal :breaked, r
  end

  def test_each_pair_allows_modification
    @cache[:a] = 1
    @cache[:b] = 1
    @cache[:c] = 1

    assert_nothing_raised do
      @cache.each_pair do |k, v|
        @cache[:z] = 1
      end
    end
  end

  def test_keys
    assert_equal [], @cache.keys

    @cache[1] = 1
    assert_equal [1], @cache.keys

    @cache[2] = 2
    assert_equal [1, 2], @cache.keys.sort
  end

  def test_values
    assert_equal [], @cache.values

    @cache[1] = 1
    assert_equal [1], @cache.values

    @cache[2] = 2
    assert_equal [1, 2], @cache.values.sort
  end

  def test_each_key
    assert_equal(@cache, (@cache.each_key {flunk}))

    @cache[1] = 1
    arr = []
    @cache.each_key {|k| arr << k}
    assert_equal [1], arr

    @cache[2] = 2
    arr = []
    @cache.each_key {|k| arr << k}
    assert_equal [1, 2], arr.sort
  end

  def test_each_value
    assert_equal(@cache, (@cache.each_value {flunk}))

    @cache[1] = 1
    arr = []
    @cache.each_value {|k| arr << k}
    assert_equal [1], arr

    @cache[2] = 2
    arr = []
    @cache.each_value {|k| arr << k}
    assert_equal [1, 2], arr.sort
  end

  def test_empty
    assert_equal true,  @cache.empty?
    @cache[:a] = 1
    assert_equal false, @cache.empty?
  end

  def test_options_validation
    assert_valid_options(nil)
    assert_valid_options({})
    assert_valid_options(:foo => :bar)
  end

  def test_initial_capacity_options_validation
    assert_valid_option(:initial_capacity, nil)
    assert_valid_option(:initial_capacity, 1)
    assert_invalid_option(:initial_capacity, '')
    assert_invalid_option(:initial_capacity, 1.0)
    assert_invalid_option(:initial_capacity, -1)
  end

  def test_load_factor_options_validation
    assert_valid_option(:load_factor, nil)
    assert_valid_option(:load_factor, 0.01)
    assert_valid_option(:load_factor, 0.75)
    assert_valid_option(:load_factor, 1)
    assert_invalid_option(:load_factor, '')
    assert_invalid_option(:load_factor, 0)
    assert_invalid_option(:load_factor, 1.1)
    assert_invalid_option(:load_factor, 2)
    assert_invalid_option(:load_factor, -1)
  end

  def test_concurency_level_options_validation
    assert_valid_option(:concurrency_level, nil)
    assert_valid_option(:concurrency_level, 1)
    assert_invalid_option(:concurrency_level, '')
    assert_invalid_option(:concurrency_level, 1.0)
    assert_invalid_option(:concurrency_level, 0)
    assert_invalid_option(:concurrency_level, -1)
  end

  private
  def assert_valid_option(option_name, value)
    assert_valid_options(option_name => value)
  end

  def assert_valid_options(options)
    assert_nothing_raised { ThreadSafe::Cache.new(options) }
  end

  def assert_invalid_option(option_name, value)
    assert_invalid_options(option_name => value)
  end

  def assert_invalid_options(options)
    assert_raise(ArgumentError) { ThreadSafe::Cache.new(options) }
  end
end