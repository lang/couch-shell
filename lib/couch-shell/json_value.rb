# -*- encoding: utf-8 -*-

require "json"

module CouchShell

  # Wraps a Ruby data structure that represents a json value. If the wrapped
  # document is of type object, members can be accessed method call syntax. To
  # avoid shadowing of object members, almost all JsonValue instance methods
  # end in ! or ?.
  #
  #   j = JsonValue.wrap({"a" => 1})
  #   j.a             # => #<JsonValue 1>
  #   j.unwrapped!    # => {"a" => 1}
  #
  # Attributes can also be accessed via []
  #
  #   j["a"]          # => #<JsonValue 1>
  #
  # Arrays elements too
  #
  #   j = JsonValue.wrap(["a", "b"])
  #   j[0]            # => #<JsonValue "a">
  #
  # The wrapped data structure mustn't be modified.
  class JsonValue < BasicObject

    def self.wrap(ruby_value)
      case ruby_value
      when ::Hash
        h = ::Hash.new
        ruby_value.each { |k, v|
          h[k] = wrap(v)
        }
        JsonValue.new(h, ruby_value)
      when ::Array
        a = ::Array.new(ruby_value.size)
        ruby_value.each_with_index { |v, i|
          a[i] = wrap(v)
        }
        JsonValue.new(a, ruby_value)
      else
        JsonValue.new(ruby_value, ruby_value)
      end
    end

    def self.parse(str)
      if str.start_with?("[") || str.start_with?("{") # optimization
        wrap(::JSON.parse(str))
      else
        # JSON parses only JSON documents, i.e. an object or an array. Thus we
        # box the given json value in an array and unbox it after parsing to
        # allow parsing of any json value.
        wrap(::JSON.parse("[#{str}]")[0])
      end
    end

    def self.rval(obj)
      if obj.respond_to?(:couch_shell_ruby_value!)
        obj.couch_shell_ruby_value!
      else
        obj
      end
    end

    def initialize(value, ruby_value)
      @value = value
      @ruby_value = ruby_value
      @type = case @value
              when ::Hash
                :object
              when ::Array
                :array
              when ::String
                :string
              when ::Numeric
                :number
              when ::TrueClass
                :boolean
              when ::FalseClass
                :boolean
              when nil
                :null
              else
                ::Kernel.raise "#{value} is not of a valid json type"
              end
    end

    def object?
      @type == :object
    end

    def array?
      @type == :array
    end

    def string?
      @type == :string
    end

    def number?
      @type == :number
    end

    def boolean?
      @type == :boolean
    end

    def null?
      @type == :null
    end

    def respond_to?(msg)
      msg == :couch_shell_format_string! || msg == :to_s ||
        msg == :couch_shell_ruby_value! ||
        (@type == :object && @value.has_key?(msg.to_s))
    end

    def method_missing(msg, *args)
      if args.empty? && @type == :object
        msg_str = msg.to_s
        if @value.has_key?(msg_str)
          return @value[msg_str]
        end
      end
      super
    end

    # Access object member (i must be a string) or array element (i must be an
    # integer). Returns a JsonValue or nil if the object member or array index
    # doesn't exist.
    def [](i)
      ri = JsonValue.rval(i)
      case ri
      when ::String
        unless @type == :object
          ::Kernel.raise ::TypeError,
            "string indexing only allowed for objects"
        end
        @value[ri]
      when ::Integer
        unless @type == :array
          ::Kernel.raise ::TypeError,
            "integer indexing only allowed for arrays"
        end
        @value[ri]
      else
        ::Kernel.raise ::TypeError,
          "index must be string or integer"
      end
    end

    def to_s(format = false)
      case @type
      when :object, :array
        if format
          ::JSON.pretty_generate(@ruby_value)
        else
          ::JSON.generate(@ruby_value)
        end
      when :null
        "null"
      else
        @ruby_value.to_s
      end
    end

    def couch_shell_format_string!
      to_s true
    end

    def delete_attr!(name)
      ::Kernel.raise ::TypeError unless @type == :object
      @ruby_value.delete(name)
      @value.delete(name)
    end

    def set_attr!(name, value)
      ::Kernel.raise ::TypeError unless @type == :object
      v = value.respond_to?(:couch_shell_ruby_value!) ?
        value.couch_shell_ruby_value! : value
      @ruby_value[name] = v
      @value[name] = JsonValue.wrap(v)
    end

    def couch_shell_ruby_value!
      @ruby_value
    end
    alias unwrapped! couch_shell_ruby_value!

    def nil?
      false
    end

    def attr_or_nil!(name)
      return nil unless @type == :object
      @value[name]
    end

    def inspect
      "#<JsonValue #{to_s}>"
    end

    def length
      raise ::TypeError, "length of #@type" unless array?
      @ruby_value.length
    end

  end

end
