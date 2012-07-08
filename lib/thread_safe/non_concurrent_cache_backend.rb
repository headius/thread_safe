module ThreadSafe
  class NonConcurrentCacheBackend
    def initialize(options = nil)
      @backend = {}
    end

    def [](key)
      @backend[key]
    end

    def []=(key, value)
      @backend[key] = value
    end

    def put_if_absent(key, value)
      if @backend.key?(key)
        @backend[key]
      else
        @backend[key] = value
        nil
      end
    end

    def key?(key)
      @backend.key?(key)
    end

    def delete(key)
      @backend.delete(key)
    end

    def clear
      @backend.clear
      self
    end

    def each_pair
      @backend.each_pair do |k, v|
        yield k, v
      end
      self
    end
  end
end