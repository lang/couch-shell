# -*- encoding: utf-8 -*-

require "couch-shell/shell"
require "couch-shell/commandline"

module CouchShell

  def self.run(args)
    server = nil
    path = nil
    user = nil

    begin
      Commandline.new { |cmd|
        cmd.arg { |arg|
          if server.nil?
            server = arg
          elsif path.nil?
            path = arg
          else
            raise Commandline::Error, "too many arguments"
          end
        }
        cmd.opt "-u", "--user=USER",
          "Connect with CouchDB as USER. Password will be asked." do |val|
          user = val
        end
        cmd.opt "-h", "--help", "Show help and exit." do
          STDOUT.puts "Usage: couch-shell [options] [--] [HOSTNAME[:PORT]] [PATH]"
          STDOUT.puts
          STDOUT.puts "Available options:"
          STDOUT.puts cmd.optlisting
          STDOUT.puts
          STDOUT.puts "Example: couch-shell -u admin 127.0.0.1:5984 mydb"
          return 0
        end
      }.process(args)
    rescue Commandline::Error => e
      STDERR.puts e.message
      STDERR.puts "Run `couch-shell -h' for help."
      return 1
    end

    shell = Shell.new(STDIN, STDOUT, STDERR)
    shell.execute "user #{user}" if user
    shell.execute "server #{server}" if server
    shell.execute "cg #{path}" if path

    shell.read_execute_loop

    0
  end

end
