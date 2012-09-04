module ThreadSafe
  module Util
    class Striped64
      class Cell < AtomicReference
        # TODO: this only adds padding after the :value slot, need to find a way to add padding before the slot
        attr_reader *(Array.new(12).map {|i| :"padding_#{i}"})

        alias_method :cas, :compare_and_set

        def cas_computed
          cas(current_value = value, yield(current_value))
        end
      end

      extend Volatile
      attr_volatile :cells, :base, :busy

      alias_method :busy?, :busy

      def initialize
        super()
        self.busy = false
        self.base = 0
      end

      def retry_update(x, hash_code, was_uncontended)
        hash     = hash_code
        collided = false # True if last slot nonempty
        while true
          if current_cells = cells
            if !(cell = current_cells.volatile_get_by_hash(hash))
              if busy?
                collided = false
              else # Try to attach new Cell
                if try_to_install_new_cell(Cell.new(x), hash) # Optimistically create and try to insert new cell
                  break
                else
                  redo # Slot is now non-empty
                end
              end
            elsif !was_uncontended # CAS already known to fail
              was_uncontended = true # Continue after rehash
            elsif cell.cas_computed {|current_value| yield current_value}
              break
            elsif current_cells.size >= CPU_COUNT || cells != current_cells # At max size or stale
              collided = false
            elsif collided && expand_table_unless_stale(current_cells)
              collided = false
              redo # Retry with expanded table
            else
              collided = true
            end
            hash = XorShiftRandom.xorshift(hash)

          elsif try_initialize_cells(x, hash) || cas_base_computed {|current_base| yield current_base}
            break
          end
        end
        self.hash_code = hash
      end

      private
      THREAD_LOCAL_KEY = "#{name}.hash_code".to_sym

      def hash_code
        Thread.current[THREAD_LOCAL_KEY] ||= XorShiftRandom.get
      end

      def hash_code=(hash)
        Thread.current[THREAD_LOCAL_KEY] = hash
      end

      def internal_reset(initial_value)
        current_cells = cells
        self.base     = initial_value
        if current_cells
          current_cells.each do |cell|
            cell.value = initial_value if cell
          end

        end
      end

      def cas_base_computed
        cas_base(current_base = base, yield(current_base))
      end

      def free?
        !busy?
      end

      def try_initialize_cells(x, hash)
        if free? && !cells
          try_in_busy do
            unless cells # Recheck under lock
              new_cells = PowerOfTwoTuple.new(2)
              new_cells.volatile_set_by_hash(hash, Cell.new(x))
              self.cells = new_cells
            end
          end
        end
      end

      def expand_table_unless_stale(current_cells)
        try_in_busy do
          if current_cells == cells # Recheck under lock
            new_cells = current_cells.next_in_size_table
            current_cells.each_with_index {|x, i| new_cells.volatile_set(i, x)}
            self.cells = new_cells
          end
        end
      end

      def try_to_install_new_cell(new_cell, hash)
        try_in_busy do
          # Recheck under lock
          if (current_cells = cells) && !current_cells.volatile_get(i = current_cells.hash_to_index(hash))
            current_cells.volatile_set(i, new_cell)
          end
        end
      end

      def try_in_busy
        if cas_busy(false, true)
          begin
            yield
          ensure
            self.busy = false
          end
        end
      end
    end
  end
end