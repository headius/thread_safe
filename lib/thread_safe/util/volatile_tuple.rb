module ThreadSafe
  module Util
    class VolatileTuple
      include Enumerable

      Tuple = defined?(Rubinius::Tuple) ? Rubinius::Tuple : Array

      def initialize(size)
        @tuple = tuple = Tuple.new(size)
        i = 0
        while i < size
          tuple[i] = AtomicReference.new
          i += 1
        end
      end

      def volatile_get(i)
        @tuple[i].get
      end

      def volatile_set(i, value)
        @tuple[i].set(value)
      end

      def compare_and_set(i, old_value, new_value)
        @tuple[i].compare_and_set(old_value, new_value)
      end
      alias_method :cas, :compare_and_set

      def size
        @tuple.size
      end

      def each
        @tuple.each {|ref| yield ref.get}
      end
    end
  end
end