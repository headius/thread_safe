require 'test/unit'
require 'thread_safe'

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