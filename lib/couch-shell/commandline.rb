# -*- encoding: utf-8 -*-

module CouchShell

  class Commandline

    class Error < StandardError
    end

    class ArgNotAllowedError < Error
      
      attr_reader :arg

      def initialize(arg)
        @arg = arg
      end

      def message
        "no argument allowed, argument `#{arg}' was given"
      end

    end

    class UnknownOptError < Error
      
      attr_reader :optname

      def initialize(optname)
        @optname = optname
      end

      def message
        "unkown option `#{optname}'"
      end

    end

    class OptArgMissingError < Error

      attr_reader :optname

      def initialize(optname)
        @optname = optname
      end

      def message
        "option `#{optname}' requires argument"
      end

    end

    class Opt

      attr_accessor :short, :long, :value, :doc, :action

      def initialize
        @short = nil
        @long = nil
        @value = nil
        @doc = nil
        @action = nil
      end

      def parse_spec!(optspec)
        value = nil
        case optspec
        when /\A--([^-= ][^= ]+)(=[^= ]+)?\z/
          raise "long option already set" if @long
          @long = $1
          value = ($2 ? $2[1..-1] : nil)
        when /\A-([^- ])( [^= ]+)?\z/
          raise "short option already set" if @short
          @short = $1
          value = ($2 ? $2[1..-1] : nil)
        else
          raise "invalid optspec `#{optspec}'"
        end
        if value
          if @value && @value != value
            raise "option value name mismatch: `#{value}' != `#{@value}'"
          end
          @value = value
        end
      end

    end

    def initialize
      @arg_action = nil
      @opts = []
      @leading_help = nil
      @trailing_help = nil
      yield self
    end

    def arg(&block)
      @arg_action = block
    end

    def opt(optspec1, optspec2 = nil, doc = nil, &block)
      raise "optspec and action block required" unless optspec1 && block
      option = Opt.new
      option.doc = doc
      option.parse_spec! optspec1
      if optspec2 && doc
        option.parse_spec! optspec2 if optspec2
      elsif optspec2
        option.doc = doc
      end
      option.action = block
      @opts << option
    end

    def optlisting(indent = "  ")
      max_value_len = @opts.map(&:value).compact.map(&:length).max || 0
      String.new.tap do |t|
        @opts.each { |opt|
          t << indent
          if opt.short
            t << "-#{opt.short} "
            if opt.value
              t << opt.value
              t << (" " * (max_value_len - opt.value.length))
            end
          else
            t << "   " << (" " * max_value_len)
          end
          t << "    "
          if opt.long
            t << "--#{opt.long}"
            t << "=#{opt.value}" if opt.value
          end
          t << "\n"
          if opt.doc
            opt.doc.each_line { |l|
              t << (indent * 3) << l
            }
          end
          t << "\n"
        }
      end
    end

    # May raise Commandline::Error or subclass thereof.
    def process(args)
      optstop = false
      opt_to_eat_arg = nil
      opt_to_eat_arg_arg = nil
      args.each { |arg|
        if optstop
          if opt_to_eat_arg
            raise OptArgMissingError.new(opt_to_eat_arg_arg)
          end
          @arg_action.call(arg)
          next
        end
        if opt_to_eat_arg
          opt_to_eat_arg.action.call(arg)
          opt_to_eat_arg = nil
          opt_to_eat_arg_arg = nil
          next
        end
        case arg
        when "--"
          optstop = true
        when /\A--([^=]*)(=.*)?\z/
          long = $1
          if long.nil? || long.empty?
            raise Error, "expected option name in `#{arg}'"
          end
          opt = @opts.find { |opt| opt.long == long }
          raise UnknownOptError.new(arg) unless opt
          if opt.value
            if $2
              opt.action.call($2[1..-1])
            else
              raise OptArgMissingError.new(arg)
            end
          else
            if $2
              raise ArgNotAllowedError.new(arg)
            else
              opt.action.call
            end
          end
        when /\A-([^-])\z/
          short = $1
          opt = @opts.find { |opt| opt.short == short }
          raise UnknownOptError.new(arg) unless opt
          if opt.value
            opt_to_eat_arg = opt
            opt_to_eat_arg_arg = arg
          else
            opt.action.call
          end
        when /\A-/
          raise UnknownOptError.new(arg)
        else
          if @arg_action
            @arg_action.call(arg)
          else
            ArgNotAllowedError.new(arg)
          end
        end
      }
      if opt_to_eat_arg
        raise OptArgMissingError.new(opt_to_eat_arg_arg)
      end
    end

  end

end
