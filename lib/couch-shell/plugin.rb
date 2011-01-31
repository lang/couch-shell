# -*- encoding: utf-8 -*-

require "unicode_utils/uppercase_char_q"
require "unicode_utils/downcase"
require "decorate"
require "couch-shell/exceptions"
require "couch-shell/plugin_utils"

module CouchShell

  class VariableInfo

    attr_reader :name
    attr_reader :prefix
    attr_reader :tags
    attr_reader :doc_line
    attr_reader :doc_text
    attr_reader :lookup_message
    attr_reader :plugin

    def initialize(opts)
      @name = opts[:name]
      @prefix = opts[:prefix]
      raise "name or prefix required" unless @name || @prefix
      raise "only name OR prefix allowed" if @name && @prefix
      @tags = [@name || @prefix].concat(opts[:tags] || [])
      @doc_line = opts[:doc_line] or raise "doc_line required"
      @doc_text = opts[:doc_text]
      @lookup_message = opts[:lookup_message] or raise "lookup_message required"
      @plugin = opts[:plugin] or raise "plugin required"
    end

    def label
      @name || "#@prefix*"
    end

  end

  class CommandInfo

    attr_reader :name
    attr_reader :tags
    attr_reader :synopsis
    attr_reader :doc_line
    attr_reader :doc_text
    attr_reader :execute_message
    attr_reader :plugin

    def initialize(opts)
      @name = opts[:name] or raise "name required"
      @tags = [@name].concat(opts[:tags] || [])
      @synopsis = opts[:synopsis]
      @doc_line = opts[:doc_line] or raise "doc_line required"
      @doc_text = opts[:doc_text]
      @execute_message = opts[:execute_message] or raise "execute_message required"
      @plugin = opts[:plugin] or raise "plugin required"
    end

  end

  class PluginInfo

    @by_class_map = {}
    @by_name_map = {}

    class << self

      def class_name_to_plugin_name(class_name)
        String.new.tap do |plugin_name|
          was_uppercase = false
          extract = class_name[/[^:]+\z/].sub(/Plugin\z/, '')
          i = 0
          lastcase = nil
          while i < extract.length
            c = extract[i]
            if UnicodeUtils.uppercase_char? c
              if lastcase != :upper
                if i > 0 && plugin_name[-1] != "_"
                  plugin_name << "_"
                end
                lastcase = :upper
              end
              plugin_name << UnicodeUtils.downcase(c, nil)
            elsif UnicodeUtils.lowercase_char? c
              if lastcase == :upper &&
                   (plugin_name.length > 1 && plugin_name[-2] != "_")
                plugin_name.insert(-2, "_")
              end
              lastcase = :lower
              plugin_name << c
            else
              lastcase = nil
              plugin_name << c
            end
            i = i + 1
          end
        end
      end

      def register(plugin_class)
        plugin_name = class_name_to_plugin_name(plugin_class.name)
        unless plugin_name =~ /\A\p{Alpha}(\p{Alpha}|\p{Digit}|_)*\z/
          raise "invalid plugin name #{plugin_name}"
        end
        pi = PluginInfo.new(plugin_name, plugin_class)
        @by_class_map[plugin_class] = pi
        @by_name_map[plugin_name] = pi
      end

      def [](class_or_name)
        @by_class_map[class_or_name] || @by_name_map[class_or_name]
      end

    end

    attr_reader :plugin_class
    attr_reader :plugin_name
    # Enumerable of VariableInfo instances.
    attr_reader :variables
    # Map of name/CommandInfo instances.
    attr_reader :commands

    def initialize(plugin_name, plugin_class)
      @plugin_class = plugin_class
      @plugin_name = plugin_name
      @variables = []
      @commands = {}
    end

    def register_command(ci)
      raise "command #{ci.name} already registered" if @commands[ci]
      @commands[ci.name] = ci
    end

    def register_variable(variable_info)
      @variables << variable_info
    end

  end

  module PluginClass

    def plugin_info
      PluginInfo[self]
    end

    def var(doc_line, opts = {})
      opts[:doc_line] = doc_line
      Decorate.decorate { |klass, method_name|
        unless opts[:name] || opts[:prefix]
          if method_name =~ /\Alookup_prefix_(.+)\z/
            opts[:prefix] = $1
          elsif method_name =~ /\Alookup_(.+)\z/
            opts[:name] = $1
          end
        end
        opts[:lookup_message] = method_name
        opts[:plugin] = plugin_info
        plugin_info.register_variable VariableInfo.new(opts)
      }
    end

    def cmd(doc_line, opts = {})
      opts[:doc_line] = doc_line
      Decorate.decorate { |klass, method_name|
        if !opts[:name] && method_name =~ /\Aexecute_(.+)\z/
          opts[:name] = $1
        end
        opts[:execute_message] = method_name
        opts[:plugin] = plugin_info
        plugin_info.register_command CommandInfo.new(opts)
      }
    end

  end

  class PluginVariablesObject < BasicObject

    def initialize(plugin)
      @plugin = plugin
    end

    def method_missing(msg, *args)
      unless args.empty?
        ::Kernel.raise ShellUserError,
          "expected plugin variable lookup: #{msg}"
      end
      varname = msg.to_s
      @plugin.plugin_info.variables.each { |vi|
        begin
          if vi.name && vi.name == varname
            return @plugin.send vi.lookup_message
          end
          if vi.prefix && varname.start_with?(vi.prefix) &&
              varname.length > vi.prefix.length
            return @plugin.send vi.lookup_message, varname[vi.prefix.length]
          end
        rescue Plugin::VarNotSet => e
          e.var = vi
          ::Kernel.raise e
        end
      }
      ::Kernel.raise ShellUserError,
        "no variable #{varname} in plugin #{@plugin.plugin_name}"
    end

  end

  class Plugin

    include PluginUtils

    def self.inherited(klass)
      klass.extend PluginClass
      PluginInfo.register(klass)
    end

    # Do not override this method, override plugin_initialization if you
    # need custom initialization logic.
    def initialize(shell)
      @_couch_shell_shell = shell
    end

    def shell
      @_couch_shell_shell
    end

    def plugin_info
      self.class.plugin_info
    end

    def plugin_name
      plugin_info.plugin_name
    end

    # Called by the shell after it instantiates the plugin. The shell
    # attribute will be already set.
    #
    # Override this method if your plugin needs custom initialization
    # logic or to alter the shell behaviour beyond adding variables and
    # commands. The default implementation does nothing.
    def plugin_initialization
    end

    def variables_object
      PluginVariablesObject.new(self)
    end

  end

end
