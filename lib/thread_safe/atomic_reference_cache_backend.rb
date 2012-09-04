module ThreadSafe
  class AtomicReferenceCacheBackend
    class Table < Util::PowerOfTwoTuple
      def cas_new_node(i, hash, key, value)
        cas(i, nil, Node.new(hash, key, value))
      end

      def try_to_cas_in_computed(i, hash, key)
        succeeded = false
        new_value = nil
        new_node  = Node.new(locked_hash = hash | LOCKED, key, NULL)
        if cas(i, nil, new_node)
          begin
            new_node.value = new_value = yield
            succeeded = true
          ensure
            volatile_set(i, nil) unless succeeded
            new_node.unlock_via_hash(locked_hash, hash)
          end
        end
        return succeeded, new_value
      end

      def try_lock_via_hash(i, node, node_hash)
        node.try_lock_via_hash(node_hash) do
          yield if volatile_get(i) == node
        end
      end
    end

    class Node
      extend Util::Volatile
      attr_volatile :hash, :value, :next

      include Util::CheapLockable

      bit_shift = Util::FIXNUM_BIT_SIZE - 2 # need 2 bits for ourselves
      MOVED     = ('10' << ('0' * bit_shift)).to_i(2) # hash field for forwarding nodes
      LOCKED    = ('01' << ('0' * bit_shift)).to_i(2) # set/tested only as a bit
      WAITING   = ('11' << ('0' * bit_shift)).to_i(2) # both bits set/tested together
      HASH_BITS = ('00' << ('1' * bit_shift)).to_i(2) # usable bits of normal node hash

      SPIN_LOCK_ATTEMPTS = Util::CPU_COUNT > 1 ? Util::CPU_COUNT * 2 : 0

      attr_reader :key

      def initialize(hash, key, value, next_node = nil)
        super()
        @key = key
        self.lazy_set_hash(hash)
        self.lazy_set_value(value)
        self.next = next_node
      end

      def try_await_lock(table, i)
        if table && i >= 0 && i < table.size # bounds check, TODO: why are we bounds checking?
          spins = SPIN_LOCK_ATTEMPTS
          randomizer = base_randomizer = Util::XorShiftRandom.get
          while equal?(table.volatile_get(i)) && self.class.locked_hash?(my_hash = hash)
            if spins >= 0
              if (randomizer = (randomizer >> 1)).even? # spin at random
                if (spins -= 1) == 0
                  Thread.pass # yield before blocking
                else
                  randomizer = base_randomizer = Util::XorShiftRandom.xorshift(base_randomizer) if randomizer.zero?
                end
              end
            elsif cas_hash(my_hash, my_hash | WAITING)
              force_aquire_lock(table, i)
              break
            end
          end
        end
      end

      def key?(key)
        @key.eql?(key)
      end

      def matches?(key, hash)
        pure_hash == hash && key?(key)
      end

      def pure_hash
        hash & HASH_BITS
      end

      def try_lock_via_hash(node_hash = hash)
        if cas_hash(node_hash, locked_hash = node_hash | LOCKED)
          begin
            yield
          ensure
            unlock_via_hash(locked_hash, node_hash)
          end
        end
      end

      def locked?
        self.class.locked_hash?(hash)
      end

      def unlock_via_hash(locked_hash, node_hash)
        unless cas_hash(locked_hash, node_hash)
          self.hash = node_hash
          cheap_synchronize { cheap_broadcast }
        end
      end

      private
      def force_aquire_lock(table, i)
        cheap_synchronize do
          if equal?(table.volatile_get(i)) && (hash & WAITING) == WAITING
            cheap_wait
          else
            cheap_broadcast # possibly won race vs signaller
          end
        end
      end

      class << self
        def locked_hash?(hash)
          (hash & LOCKED) != 0
        end
      end
    end

    NULL         = Object.new
    NOW_RESIZING = -1

    # shorthands
    MOVED     = Node::MOVED
    LOCKED    = Node::LOCKED
    WAITING   = Node::WAITING
    HASH_BITS = Node::HASH_BITS

    DEFAULT_CAPACITY     = 16
    TRANSFER_BUFFER_SIZE = 32
    MAX_CAPACITY         = Util::MAX_INT

    extend Util::Volatile
    attr_volatile :table, :size_control

    def initialize(options = nil)
      super()
      @counter = Util::Adder.new

      initial_capacity  = options && options[:initial_capacity] || DEFAULT_CAPACITY
      concurrency_level = options && options[:concurrency_level]

      initial_capacity = concurrency_level if concurrency_level && concurrency_level > initial_capacity # Use at least as many bins

      self.size_control = (capacity = table_size_for(initial_capacity)) > MAX_CAPACITY ? MAX_CAPACITY : capacity
    end

    def [](key)
      internal_get(key)
    end

    def key?(key)
      internal_get(key, NULL) != NULL
    end

    def []=(key, value)
      internal_put(key, value)
      value
    end

    def compute_if_absent(key)
      hash          = key_hash(key)
      current_table = table || initialize_table
      while true
        if !(node = current_table.volatile_get(i = current_table.hash_to_index(hash)))
          succeeded, new_value = current_table.try_to_cas_in_computed(i, hash, key) { yield }
          if succeeded
            increment_size
            return new_value
          end
        elsif (node_hash = node.hash) == MOVED
          current_table = node.key
        elsif NULL != (current_value = find_value_in_node_list(node, key, hash, node_hash & HASH_BITS))
          return current_value
        elsif Node.locked_hash?(node_hash)
          try_await_lock(current_table, i, node)
        else
          succeeded, value = attempt_internal_compute_if_absent(key, hash, current_table, i, node, node_hash) { yield }
          return value if succeeded
        end
      end
    end

    if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'rbx'
      def compute_if_absent(key)
        hash          = key_hash(key)
        current_table = table || initialize_table
        while true
          if !(node = current_table.volatile_get(i = current_table.hash_to_index(hash)))
            succeeded, new_value = current_table.try_to_cas_in_computed(i, hash, key) { yield }
            if succeeded
              increment_size
              return new_value
            end
          elsif (node_hash = node.hash) == MOVED
            current_table = node.key
          # TODO: fix this
          # START Rubinius hack
          # Rubinius seems to go crazy on the full test_cache_loop run without this inlined first iteration of find_value_in_node_list
          elsif (node_hash & HASH_BITS) == hash && node.key?(key) && NULL != (current_value = node.value)
            return current_value
          # END Rubinius hack
          elsif NULL != (current_value = find_value_in_node_list(node, key, hash, node_hash & HASH_BITS))
            return current_value
          elsif Node.locked_hash?(node_hash)
            try_await_lock(current_table, i, node)
          else
            succeeded, value = attempt_internal_compute_if_absent(key, hash, current_table, i, node, node_hash) { yield }
            return value if succeeded
          end
        end
      end
    end

    def replace_pair(key, old_value, new_value)
      NULL != internal_replace(key, new_value) {|current_value| current_value == old_value}
    end

    def replace_if_exists(key, new_value)
      if (result = internal_replace(key, new_value)) && NULL != result
        result
      end
    end

    def get_and_set(key, value)
      internal_put(key, value)
    end

    def delete(key)
      replace_if_exists(key, NULL)
    end

    def delete_pair(key, value)
      result = internal_replace(key, NULL) {|current_value| value == current_value}
      if result && NULL != result
        !!result
      else
        false
      end
    end

    def each_pair
      return self unless current_table = table
      current_table_size = base_size = current_table.size
      i = base_index = 0
      while base_index < base_size
        if node = current_table.volatile_get(i)
          if node.hash == MOVED
            current_table      = node.key
            current_table_size = current_table.size
          else
            begin
              if NULL != (value = node.value) # skip deleted or special nodes
                yield node.key, value
              end
            end while node = node.next
          end
        end

        if (i_with_base = i + base_size) < current_table_size
          i = i_with_base # visit upper slots if present
        else
          i = base_index += 1
        end
      end
      self
    end

    def size
      (sum = @counter.sum) < 0 ? 0 : sum # ignore transient negative values
    end

    def empty?
      size == 0
    end

    def clear
      return self unless current_table = table
      current_table_size = current_table.size
      deleted_count = i = 0
      while i < current_table_size
        if !(node = current_table.volatile_get(i))
          i += 1
        elsif (node_hash = node.hash) == MOVED
          current_table      = node.key
          current_table_size = current_table.size
        elsif Node.locked_hash?(node_hash)
          decrement_size(deleted_count) # opportunistically update count
          deleted_count = 0
          node.try_await_lock(current_table, i)
        else
          current_table.try_lock_via_hash(i, node, node_hash) do
            begin
              deleted_count += 1 if NULL != node.value # recheck under lock
              node.value = nil
            end while node = node.next
            current_table.volatile_set(i, nil)
            i += 1
          end
        end
      end
      decrement_size(deleted_count)
      self
    end

    private
    def initialize_copy(other)
      super
      @counter = Util::Adder.new
      self.table = nil
      self.size_control = (other_table = other.table) ? other_table.size : DEFAULT_CAPACITY
      self
    end

    def internal_get(key, else_value = nil)
      hash          = key_hash(key)
      current_table = table
      while current_table
        node = current_table.volatile_get_by_hash(hash)
        current_table =
          while node
            if (node_hash = node.hash) == MOVED
              break node.key
            elsif (node_hash & HASH_BITS) == hash && node.key?(key) && NULL != (value = node.value)
              return value
            end
            node = node.next
          end
      end
      else_value
    end

    def find_value_in_node_list(node, key, hash, pure_hash)
      do_check_for_resize = false
      while true
        if pure_hash == hash && node.key?(key) && NULL != (value = node.value)
          return value
        elsif node = node.next
          do_check_for_resize = true # at least 2 nodes -> check for resize
          pure_hash = node.pure_hash
        else
          return NULL
        end
      end
    ensure
      check_for_resize if do_check_for_resize
    end

    def attempt_internal_compute_if_absent(key, hash, current_table, i, node, node_hash)
      added = false
      current_table.try_lock_via_hash(i, node, node_hash) do
        while true
          if node.matches?(key, hash) && NULL != (value = node.value)
            return true, value
          end
          last = node
          unless node = node.next
            last.next = Node.new(hash, key, value = yield)
            added = true
            increment_size
            return true, value
          end
        end
      end
    ensure
      check_for_resize if added
    end

    def internal_replace(key, value, &block)
      hash          = key_hash(key)
      current_table = table
      while current_table
        if !(node = current_table.volatile_get(i = current_table.hash_to_index(hash)))
          break
        elsif (node_hash = node.hash) == MOVED
          current_table = node.key
        elsif (node_hash & HASH_BITS) != hash && !node.next # precheck
          break # rules out possible existence
        elsif Node.locked_hash?(node_hash)
          try_await_lock(current_table, i, node)
        else
          succeeded, old_value = attempt_internal_replace(key, value, hash, current_table, i, node, node_hash, &block)
          return old_value if succeeded
        end
      end
      NULL
    end

    def attempt_internal_replace(key, value, hash, current_table, i, node, node_hash)
      current_table.try_lock_via_hash(i, node, node_hash) do
        predecessor_node = nil
        old_value        = NULL
        begin
          if node.matches?(key, hash) && NULL != (current_value = node.value)
            if !block_given? || yield(current_value)
              old_value = current_value
              if NULL == (node.value = value)
                if predecessor_node
                  predecessor_node.next = node.next
                else
                  current_table.volatile_set(i, node.next)
                end
                decrement_size
              end
            end
            break
          end

          predecessor_node = node
        end while node = node.next

        return true, old_value
      end
    end

    def internal_put(key, value)
      hash          = key_hash(key)
      current_table = table || initialize_table
      while current_table
        if !(node = current_table.volatile_get(i = current_table.hash_to_index(hash)))
          if current_table.cas_new_node(i, hash, key, value)
            increment_size
            break
          end
        elsif (node_hash = node.hash) == MOVED
          current_table = node.key
        elsif Node.locked_hash?(node_hash)
          try_await_lock(current_table, i, node)
        else
          succeeded, old_value = attempt_internal_put(key, value, hash, current_table, i, node, node_hash)
          return old_value if succeeded
        end
      end
    end

    def attempt_internal_put(key, value, hash, current_table, i, node, node_hash)
      node_nesting = nil
      current_table.try_lock_via_hash(i, node, node_hash) do
        node_nesting    = 1
        old_value       = nil
        found_old_value = false
        while node
          if node.matches?(key, hash) && NULL != (old_value = node.value)
            found_old_value = true
            node.value = value
            break
          end
          last = node
          unless node = node.next
            last.next = Node.new(hash, key, value)
            break
          end
          node_nesting += 1
        end

        return true, old_value if found_old_value
        increment_size
        true
      end
    ensure
      check_for_resize if node_nesting && (node_nesting > 1 || current_table.size <= 64)
    end

    def try_await_lock(current_table, i, node)
      check_for_resize # try resizing if can't get lock
      node.try_await_lock(current_table, i)
    end

    def key_hash(key)
      key.hash & HASH_BITS
    end

    def table_size_for(entry_count)
      size = 2
      size <<= 1 while size < entry_count
      size
    end

    def initialize_table
      until current_table ||= table
        if (size_ctrl = size_control) == NOW_RESIZING
          Thread.pass # lost initialization race; just spin
        else
          try_in_resize_lock(current_table, size_ctrl) do
            initial_size = size_ctrl > 0 ? size_ctrl : DEFAULT_CAPACITY
            current_table = self.table = Table.new(initial_size)
            initial_size - (initial_size >> 2) # 75% load factor
          end
        end
      end
      current_table
    end

    def check_for_resize
      while (current_table = table) && MAX_CAPACITY > (table_size = current_table.size) && NOW_RESIZING != (size_ctrl = size_control) && size_ctrl < @counter.sum
        try_in_resize_lock(current_table, size_ctrl) do
          self.table = rebuild(current_table)
          (table_size << 1) - (table_size >> 1) # 75% load factor
        end
      end
    end

    def try_in_resize_lock(current_table, size_ctrl)
      if cas_size_control(size_ctrl, NOW_RESIZING)
        begin
          if current_table == table # recheck under lock
            size_ctrl = yield # get new size_control
          end
        ensure
          self.size_control = size_ctrl
        end
      end
    end

    def rebuild(table)
      old_table_size = table.size
      new_table      = table.next_in_size_table
      # puts "#{old_table_size} -> #{new_table.size}"
      forwarder      = Node.new(MOVED, new_table, NULL)
      rev_forwarder  = nil
      locked_indexes = nil # holds bins to revisit; nil until needed
      locked_arr_idx = 0
      bin            = old_table_size - 1
      i              = bin
      while true
        if !(node = table.volatile_get(i))
          # no lock needed (or available) if bin >= 0
          redo unless (bin >= 0 ? table.cas(i, nil, forwarder) : lock_and_clean_up_reverse_forwarders(table, old_table_size, new_table, i, forwarder))
        elsif Node.locked_hash?(node_hash = node.hash)
          locked_indexes ||= Array.new
          if bin < 0 && locked_arr_idx > 0
            locked_arr_idx -= 1
            i, locked_indexes[locked_arr_idx] = locked_indexes[locked_arr_idx], i # swap with another bin
            redo
          end
          if bin < 0 || locked_indexes.size >= TRANSFER_BUFFER_SIZE
            node.try_await_lock(table, i) # no other options -- block
            redo
          end
          rev_forwarder ||= Node.new(MOVED, table, NULL)
          redo unless table.volatile_get(i) == node && node.locked? # recheck before adding to list
          locked_indexes << i
          new_table.volatile_set(i, rev_forwarder)
          new_table.volatile_set(i + old_table_size, rev_forwarder)
        else
          redo unless split_old_bin(table, new_table, i, node, node_hash, forwarder)
        end

        if bin > 0
          i = (bin -= 1)
        elsif locked_indexes && !locked_indexes.empty?
          bin = -1
          i = locked_indexes.pop
          locked_arr_idx = locked_indexes.size - 1
        else
          return new_table
        end
      end
    end

    def lock_and_clean_up_reverse_forwarders(old_table, old_table_size, new_table, i, forwarder)
      # transiently use a locked forwarding node
      locked_forwarder = Node.new(moved_locked_hash = MOVED | LOCKED, new_table, NULL)
      if old_table.cas(i, nil, locked_forwarder)
        new_table.volatile_set(i, nil) # kill the potential reverse forwarders
        new_table.volatile_set(i + old_table_size, nil) # kill the potential reverse forwarders
        old_table.volatile_set(i, forwarder)
        locked_forwarder.unlock_via_hash(moved_locked_hash, MOVED)
        true
      end
    end

    def split_old_bin(table, new_table, i, node, node_hash, forwarder)
      table.try_lock_via_hash(i, node, node_hash) do
        split_bin(new_table, i, node, node_hash)
        table.volatile_set(i, forwarder)
      end
    end

    def split_bin(new_table, i, node, node_hash)
      bit          = new_table.size >> 1 # bit to split on
      run_bit      = node_hash & bit
      last_run     = nil
      low          = nil
      high         = nil
      current_node = node
      # this optimises for the lowest amount of volatile writes and objects created
      while current_node = current_node.next
        unless (b = current_node.hash & bit) == run_bit
          run_bit  = b
          last_run = current_node
        end
      end
      if run_bit == 0
        low = last_run
      else
        high = last_run
      end
      current_node = node
      until current_node == last_run
        pure_hash = current_node.pure_hash
        if (pure_hash & bit) == 0
          low = Node.new(pure_hash, current_node.key, current_node.value, low)
        else
          high = Node.new(pure_hash, current_node.key, current_node.value, high)
        end
        current_node = current_node.next
      end
      new_table.volatile_set(i, low)
      new_table.volatile_set(i + bit, high)
    end

    def increment_size
      @counter.increment
    end

    def decrement_size(by = 1)
      @counter.add(-by)
    end
  end
end