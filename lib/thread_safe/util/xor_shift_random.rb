module ThreadSafe
  module Util
    module XorShiftRandom
      extend self
      MAX_XOR_SHIFTABLE_INT = MAX_INT - 1

      def get
        Kernel.rand(MAX_XOR_SHIFTABLE_INT) + 1 # 0 can't be xorshifted
      end

      # xorshift based on: http://www.jstatsoft.org/v08/i14/paper
      if 0.size == 4
        # using the "yˆ=y>>a; yˆ=y<<b; yˆ=y>>c;" transform with the (a,b,c) tuple with values (3,1,14) to minimise Bignum overflows
        def xorshift(x)
          x ^= x >> 3
          x ^= (x << 1) & MAX_INT # cut-off Bignum overflow
          x ^= x >> 14
        end
      else
        # using the "yˆ=y>>a; yˆ=y<<b; yˆ=y>>c;" transform with the (a,b,c) tuple with values (1,1,54) to minimise Bignum overflows
        def xorshift(x)
          x ^= x >> 1
          x ^= (x << 1) & MAX_INT # cut-off Bignum overflow
          x ^= x >> 54
        end
      end
    end
  end
end