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

    attr_reader :type
    attr_reader :ruby_value

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
                raise "#{value.class} is not a valid json type"
              end
    end

    def respond_to?(msg)
      msg == :format || msg == :couch_shell_format_string ||
        msg == :type || msg == :ruby_value || msg == :to_s ||
        (@type == :object && @value.has_key?(msg.to_s)) ||
        @value.respond_to?(msg)
    end

    def method_missing(msg, *args)
      if args.empty? && @type == :object
        msg_str = msg.to_s
        if @value.has_key?(msg_str)
          return @value[msg_str]
        end
      end
      @value.__send__(msg, *args)
    end

    def to_s
      case type
      when :object, :array
        ::JSON.generate(@ruby_value)
      when :null
        "null"
      else
        @ruby_value.to_s
      end
    end

    def format
      case type
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

  end

end
