require 'thread'
require 'test/unit'
require 'thread_safe'
require File.join(File.dirname(__FILE__), "test_helper")

Thread.abort_on_exception = true

class TestCacheTorture < Test::Unit::TestCase
  class HashCollisionKey
    attr_reader :hash, :key
    def initialize(key)
      @key  = key
      @hash = key.hash % 8
    end

    def eql?(other)
      other.kind_of?(HashCollisionKey) && @key.eql?(other.key)
    end

    def even?
      @key.even?
    end

    def <=>(other) # HashCollisionKeys should only be partially ordered (this tests CHVM8's TreeNodes)
      (@key.odd? && other.key.odd?) ? 0 : @key <=> other.key
    end
  end

  THREAD_COUNT  = 40
  KEY_COUNT     = (((2**13) - 2) * 0.75).to_i # get close to the doubling cliff
  LOW_KEY_COUNT = (((2**8 ) - 2) * 0.75).to_i # get close to the doubling cliff

  ZERO_VALUE_CACHE_SETUP = lambda do |options, keys|
    cache = ThreadSafe::Cache.new
    keys.each {|key| cache[key] = 0}
    cache
  end

  DEFAULTS = {
    :key_count => KEY_COUNT,
    :thread_count => THREAD_COUNT,
    :loop_count => 1,
    :prelude => '',
    :cache_setup => lambda {|options, keys| ThreadSafe::Cache.new}
  }

  LOW_KEY_COUNT_OPTIONS    = {:loop_count => 150,    :key_count => LOW_KEY_COUNT}
  SINGLE_KEY_COUNT_OPTIONS = {:loop_count => 1_000,  :key_count => 1}

  def test_concurrency
    code = <<-RUBY_EVAL
      cache[key]
      cache[key] = key
      cache[key]
      cache.delete(key)
    RUBY_EVAL
    do_thread_loop(:concurrency, code)
  end

  def test_put_if_absent
    do_thread_loop(:put_if_absent, 'acc += 1 unless cache.put_if_absent(key, key)', :key_count => 100_000) do |result, cache, options|
      assert_equal(options[:key_count], sum(result))
      assert_equal(options[:key_count], cache.size)
    end
  end

  def test_compute_if_absent
    code = 'cache.compute_if_absent(key) { acc += 1; key }'
    do_thread_loop(:compute_if_absent, code) do |result, cache, options|
      assert_equal(options[:key_count], sum(result))
      assert_equal(options[:key_count], cache.size)
    end
  end

  def test_compute_put_if_absent
    code = <<-RUBY_EVAL
      if key.even?
        cache.compute_if_absent(key) { acc += 1; key }
      else
        acc += 1 unless cache.put_if_absent(key, key)
      end
    RUBY_EVAL
    do_thread_loop(:compute_put_if_absent, code) do |result, cache, options|
      assert_equal(options[:key_count], sum(result))
      assert_equal(options[:key_count], cache.size)
    end
  end

  def test_add_remove_to_zero
    add_remove_to_zero
    add_remove_to_zero(LOW_KEY_COUNT_OPTIONS)
    add_remove_to_zero(SINGLE_KEY_COUNT_OPTIONS)
  end

  def test_add_remove
    add_remove
    add_remove(LOW_KEY_COUNT_OPTIONS)
    add_remove(SINGLE_KEY_COUNT_OPTIONS)
  end

  def test_add_remove_indiscriminate
    add_remove_indiscriminate
    add_remove_indiscriminate(LOW_KEY_COUNT_OPTIONS)
    add_remove_indiscriminate(SINGLE_KEY_COUNT_OPTIONS)
  end

  def test_count_up
    count_up
    count_up(LOW_KEY_COUNT_OPTIONS)
    count_up(SINGLE_KEY_COUNT_OPTIONS)
  end

  def test_count_race
    prelude = 'change = (rand(2) == 1) ? 1 : -1'
    code = <<-RUBY_EVAL
      v = cache[key]
      acc += change if cache.replace_pair(key, v, v + change)
    RUBY_EVAL
    do_thread_loop(:count_race, code, :loop_count => 5, :prelude => prelude, :cache_setup => ZERO_VALUE_CACHE_SETUP) do |result, cache, options|
      assert_equal(sum(cache.values), sum(result))
      assert_equal(options[:key_count], cache.size)
    end
  end

  private
  def add_remove(opts = {})
    prelude = 'do_add = rand(2) == 1'
    code = <<-RUBY_EVAL
      if do_add
        acc += 1 unless cache.put_if_absent(key, key)
      else
        acc -= 1 if cache.delete_pair(key, key)
      end
    RUBY_EVAL
    do_thread_loop(:add_remove, code, {:loop_count => 5, :prelude => prelude}.merge(opts)) do |result, cache, options|
      assert_equal(cache.size, sum(result))
    end
  end

  def add_remove_indiscriminate(opts = {})
    prelude = 'do_add = rand(2) == 1'
    code = <<-RUBY_EVAL
      if do_add
        acc += 1 unless cache.put_if_absent(key, key)
      else
        acc -= 1 if cache.delete(key)
      end
    RUBY_EVAL
    do_thread_loop(:add_remove, code, {:loop_count => 5, :prelude => prelude}.merge(opts)) do |result, cache, options|
      assert_equal(cache.size, sum(result))
    end
  end

  def count_up(opts = {})
    code = <<-RUBY_EVAL
      v = cache[key]
      acc += 1 if cache.replace_pair(key, v, v + 1)
    RUBY_EVAL
    do_thread_loop(:count_up, code, {:loop_count => 5, :cache_setup => ZERO_VALUE_CACHE_SETUP}.merge(opts)) do |result, cache, options|
      assert_equal(sum(cache.values), sum(result))
      assert_equal(options[:key_count], cache.size)
    end
  end

  def add_remove_to_zero(opts = {})
    code = <<-RUBY_EVAL
      acc += 1 unless cache.put_if_absent(key, key)
      acc -= 1 if cache.delete_pair(key, key)
    RUBY_EVAL
    do_thread_loop(:add_remove_to_zero, code, {:loop_count => 5}.merge(opts)) do |result, cache, options|
      assert_equal(cache.size, sum(result))
    end
  end

  def do_thread_loop(name, code, options = {}, &block)
    options = DEFAULTS.merge(options)
    meth    = define_loop name, code, options[:prelude]
    assert_nothing_raised do
      keys = to_keys_array(options[:key_count])
      run_thread_loop(meth, keys, options, &block)

      if options[:key_count] > 1
        options[:key_count] = (options[:key_count] / 20).to_i
        keys = to_hash_collision_keys_array(options[:key_count])
        run_thread_loop(meth, keys, options.merge(:loop_count => (options[:loop_count] * 5)), &block)
      end
    end
  end

  def run_thread_loop(meth, keys, options)
    cache  = options[:cache_setup].call(options, keys)
    barier = ThreadSafe::Test::Barier.new(options[:thread_count])
    t      = Time.now
    result = (1..options[:thread_count]).map do
      Thread.new do
        setup_sync_and_start_loop(meth, cache, keys, barier, options[:loop_count])
      end
    end.map(&:value).tap{|x| puts(([{:meth => meth, :time => "#{Time.now - t}s", :loop_count => options[:loop_count], :key_count => keys.size}] + x).inspect)}
    yield result, cache, options if block_given?
  end

  def setup_sync_and_start_loop(meth, cache, keys, barier, loop_count)
    my_keys = keys.shuffle
    barier.await
    if my_keys.size == 1
      key = my_keys.first
      send("#{meth}_single_key", cache, key, loop_count)
    else
      send("#{meth}_multiple_keys", cache, my_keys, loop_count)
    end
  end

  def define_loop(name, body, prelude)
    inner_meth_name = :"_#{name}_loop_inner"
    outer_meth_name = :"_#{name}_loop_outer"
    # looping is splitted into the "loop methods" to trigger the JIT
    self.class.class_eval <<-RUBY_EVAL, __FILE__, __LINE__ + 1
      def #{inner_meth_name}_multiple_keys(cache, keys, i, length, acc)
        #{prelude}
        target = i + length
        while i < target
          key = keys[i]
          #{body}
          i += 1
        end
        acc
      end unless method_defined?(:#{inner_meth_name}_multiple_keys)

      def #{inner_meth_name}_single_key(cache, key, i, length, acc)
        #{prelude}
        target = i + length
        while i < target
          #{body}
          i += 1
        end
        acc
      end unless method_defined?(:#{inner_meth_name}_single_key)

      def #{outer_meth_name}_multiple_keys(cache, keys, loop_count)
        total_length = keys.size
        acc = 0
        inc = 100
        loop_count.times do
          i = 0
          pre_loop_inc = total_length % inc
          acc = #{inner_meth_name}_multiple_keys(cache, keys, i, pre_loop_inc, acc)
          i += pre_loop_inc
          while i < total_length
            acc = #{inner_meth_name}_multiple_keys(cache, keys, i, inc, acc)
            i += inc
          end
        end
        acc
      end unless method_defined?(:#{outer_meth_name}_multiple_keys)

      def #{outer_meth_name}_single_key(cache, key, loop_count)
        acc = 0
        i   = 0
        while i < loop_count
          acc = #{inner_meth_name}_single_key(cache, key, 0, 100, acc)
          i += 1
        end
        acc
      end unless method_defined?(:#{outer_meth_name}_single_key)
    RUBY_EVAL
    outer_meth_name
  end

  def to_keys_array(key_count)
    arr = []
    key_count.times {|i| arr << i}
    arr
  end

  def to_hash_collision_keys_array(key_count)
    to_keys_array(key_count).map {|key| HashCollisionKey.new(key)}
  end

  def sum(result)
    result.inject(0) {|acc, i| acc + i}
  end
end