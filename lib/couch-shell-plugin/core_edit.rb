# -*- encoding: utf-8 -*-

require "couch-shell/plugin"

module CouchShell

  class CoreEditPlugin < Plugin

    def plugin_initialization
      @edittext = nil
    end

    var "Text saved by the last invocation of edit."
    def lookup_edittext
      @edittext or raise VarNotSet
    end

    cmd "Edit a document in your editor.",
      synopsis: "[URL]"
    def execute_edit(argstr)
      url = shell.interpolate(argstr)
      res = request! "GET", url, nil, false
      doc = res.json_value.to_s(true)
      new_doc = edittext!(doc)
      if new_doc == doc
        shell.msg "Document hasn't changed. Nothing to submit."
        return
      end
      continue? "Press ENTER to PUT updated document on server " +
                "or CTRL+C to cancel "
      unless shell.request("PUT", url, new_doc).ok?
        shell.msg "recover document text with `print edittext'"
      end
    end

  end

end
