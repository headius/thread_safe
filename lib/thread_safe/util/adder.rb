module ThreadSafe
  module Util
    class Adder < Striped64
      def add(x)
        if (current_cells = cells) || !cas_base_computed {|current_base| current_base + x}
          was_uncontended = true
          hash            = hash_code
          unless current_cells && (cell = current_cells.volatile_get_by_hash(hash)) && (was_uncontended = cell.cas_computed {|current_value| current_value + x})
            retry_update(x, hash, was_uncontended) {|current_value| current_value + x}
          end
        end
      end

      def increment
        add(1)
      end

      def decrement
        add(-1)
      end

      def sum
        x = base
        if current_cells = cells
          current_cells.each do |cell|
            x += cell.value if cell
          end
        end
        x
      end

      def reset
        internal_reset(0)
      end
    end
  end
end