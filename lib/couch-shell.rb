# -*- encoding: utf-8 -*-

require "couch-shell/shell"

module CouchShell

  VERSION = "0.0.1"

  def self.run(args)
    puts "couch-shell #{VERSION}"
    shell = Shell.new(STDIN, STDOUT, STDERR)
    if ARGV[0]
      shell.server = ARGV[0]
    end
    if ARGV[1]
      shell.cd ARGV[1], true
    end
    shell.repl
    exit 0
  end

end
