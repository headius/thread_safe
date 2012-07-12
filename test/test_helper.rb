require 'thread'

module ThreadSafe
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
end