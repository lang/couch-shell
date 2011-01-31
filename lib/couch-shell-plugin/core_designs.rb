# -*- encoding: utf-8 -*-

require "couch-shell/plugin"

module CouchShell

  class CoreDesignsPlugin < Plugin

    def all_designs_url
      '/' + dbname! + '/_all_docs?startkey="_design/"&endkey="_design0"'
    end

    cmd "Get a list of design names in current database."
    def execute_designs(argstr)
      raise ShellError, "argument not allowed" if argstr
      res = request!("GET", all_designs_url, nil, false)
      res.json["rows"].each { |row|
        shell.stdout.puts row["key"].sub(%r{\A_design/}, '')
      }
    end

  end

end
