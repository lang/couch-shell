# -*- encoding: utf-8 -*-

require "couch-shell/shell"
require "couch-shell/version"

module CouchShell

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
