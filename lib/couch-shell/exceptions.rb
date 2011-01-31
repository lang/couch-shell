# -*- encoding: utf-8 -*-

module CouchShell

  class Quit < Exception
  end

  class ShellUserError < Exception
  end

  class UndefinedVariable < ShellUserError

    attr_reader :varname

    def initialize(varname)
      @varname = varname
    end

  end

  class NoSuchPluginRegistered < ShellUserError

    attr_reader :plugin_name

    def initialize(plugin_name)
      @plugin_name = plugin_name
    end

    def message
      "No such plugin registered: #@plugin_name"
    end

  end

  class NoSuchCommandInPlugin < ShellUserError

    attr_reader :plugin_name
    attr_reader :command_name

    def initialize(plugin_name, command_name)
      @plugin_name = plugin_name
      @command_name = command_name
    end

    def message
      "Plugin #@plugin_name doesn't define a #@command_name command."
    end

  end

  class NoSuchCommand < ShellUserError
    
    attr_reader :command_name

    def initialize(command_name)
      @command_name = command_name
    end

    def message
      "No such command: #@command_name"
    end

  end

end
