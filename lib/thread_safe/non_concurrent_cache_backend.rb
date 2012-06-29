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

    def key?(key)
      @backend.key?(key)
    end

    def delete(key)
      @backend.delete(key) do
        return false
      end
      true
    end
  end
end