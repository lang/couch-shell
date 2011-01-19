# -*- encoding: utf-8 -*-

module CouchShell

  # Not threadsafe!
  class RingBuffer

    class UninitializedAccess < StandardError

      attr_reader :index

      def initialize(index)
        @index = index
      end

      def message
        "uninitalized RingBuffer access at index #@index"
      end

    end

    def initialize(size)
      @ary = Array.new(size, nil)
      @index = nil
      @written = 0
    end

    def size
      @ary.size
    end

    def initialized_size
      @written
    end

    def empty?
      @written == 0
    end

    def current
      if @index.nil?
        if block_given?
          nil
        else
          raise UninitializedAccess.new(0)
        end
      else
        if block_given?
          yield @ary[index]
        else
          @ary[index]
        end
      end
    end

    def readable_index?(i)
      i >= 0 && i < @written
    end

    # index of current (last written) element, or nil if empty
    def index
      @index
    end

    def [](i)
      i = i.to_int
      if i >= @written
        raise UninitializedAccess.new(i)
      end
      @ary[i]
    end

    def <<(elem)
      if @index.nil? || @index == size - 1
        @index = 0
      else
        @index += 1
      end
      @ary[@index] = elem
      if @written < @index + 1
        @written = @index + 1
      end
    end

  end

end
