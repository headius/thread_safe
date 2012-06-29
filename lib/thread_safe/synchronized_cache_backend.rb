module ThreadSafe
  class SynchronizedCacheBackend < NonConcurrentCacheBackend
    require 'mutex_m'
    include Mutex_m

    def [](key)
      synchronize { super }
    end

    def []=(key, value)
      synchronize { super }
    end

    def key?(key)
      synchronize { super }
    end

    def delete(key)
      synchronize { super }
    end

    def clear
      synchronize { super }
    end

    def each_pair
      collection = []
      synchronize do
        super do |k, v|
          collection << k << v
        end
      end

      i = 0
      total = collection.length

      while i < total
        yield collection[i], collection[i + 1]
        i += 2
      end

      self
    end
  end
end