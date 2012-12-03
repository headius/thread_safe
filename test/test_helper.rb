require 'thread'

module ThreadSafe
  module Test
    class Latch
      def initialize(count = 1)
        @count = count
        @mutex = Mutex.new
        @cond  = ConditionVariable.new
      end

      def release
        @mutex.synchronize do
          @count -= 1 if @count > 0
          @cond.broadcast if @count.zero?
        end
      end

      def await
        @mutex.synchronize do
          @cond.wait @mutex if @count > 0
        end
      end
    end

    class Barier < Latch
      def await
        @mutex.synchronize do
          if @count.zero? # fall through
          elsif @count > 0
            @count -= 1
            @count.zero? ? @cond.broadcast : @cond.wait(@mutex)
          end
        end
      end
    end

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
  end
end