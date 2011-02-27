# -*- encoding: utf-8 -*-

require "couch-shell/plugin"

module CouchShell

  class CoreHelpPlugin < Plugin

    INTRO = <<-EOF
    couch-shell accepts input in the form of

    >> COMMAND [ARGS]

    The [] brackets indicate that ARGS are optional, depending on
    COMMAND. This convention is used in all couch-shell help.

    To get a list of commands, enter:

    >> help commands

    couch-shell also defines a couple variables. You can print a
    variable value with:

    >> print VAR

    or:

    >> format VAR

    To get a list of variables, enter:

    >> help vars

    Commands and variables are organized in plugins. To get a list of
    plugins, enter:

    >> help plugins

    If you're new to couch-shell, start by reading about the get, put,
    post, delete and cd commands.
    EOF

    cmd "Get help.", synopsis: "[TOPIC]"
    def execute_help(argstr)
      argstr = argstr && argstr.downcase
      case argstr
      when nil
        shell.stdout.print remove_base_indent(INTRO)
      when "commands"
        help_commands
      when "vars", "variables"
        help_vars
      end
    end

    def help_commands
    end

    def help_vars
      stdout.puts "Available unqualified variables:"
      stdout.puts
      variable_infos.each { |vi|
        stdout.puts "  #{vi.label} (from #{vi.plugin.plugin_name})"
        stdout.puts "    #{vi.doc_line}"
        stdout.puts
      }
    end

    def remove_base_indent(str)
      lines = str.lines.map(&:chomp)
      i = lines.map { |line|
        line =~ /^( +)[^ ]/ && $1.length
      }.compact.min
      lines.map { |line| "#{line[i..-1]}\n" }.join
    end

  end

end
