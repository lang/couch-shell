# -*- encoding: utf-8 -*-

require "json"

module CouchShell

  class JsonValue < BasicObject

    def self.wrap(ruby_value)
      case ruby_value
      when ::Hash
        h = ::Hash.new(ruby_value.size)
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

    def respond_to?(msg)
      msg == :format || msg == :couch_shell_format_string ||
        msg == :type || msg == :ruby_value || msg == :to_s ||
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

    def [](i)
      ::Kernel.raise ::TypeError unless @type == :array
      @value[i]
    end

    def to_s
      case @type
      when :object, :array
        ::JSON.generate(@ruby_value)
      when :null
        "null"
      else
        @ruby_value.to_s
      end
    end

    def format
      case @type
      when :object, :array
        ::JSON.pretty_generate(@ruby_value)
      when :null
        "null"
      when
        @ruby_value.to_s
      end
    end

    def couch_shell_format_string
      format
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

    def nil?
      false
    end

    def attr_or_nil!(name)
      return nil unless @type == :object
      @value[name]
    end

  end

end
