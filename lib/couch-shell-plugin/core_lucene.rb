# -*- encoding: utf-8 -*-

require "couch-shell/plugin"

module CouchShell

  class CoreLucenePlugin < Plugin

    def plugin_initialization
      @ftitext = nil
    end

    var "Text saved by the last invocation of editfti."
    def lookup_ftitext
      @ftitext or raise VarNotSet
    end

    cmd "Edit fulltext index function in your editor.",
      synopsis: "DESIGN FULLTEXTINDEX"
    def execute_editfti(argstr)
      dbname = dbname!
      design_name, index_name = argstr.split(/\s+/, 2) if argstr
      if design_name.nil? || index_name.nil?
        raise ShellError, "design and fulltext index name required"
      end
      res = request! "GET", "/#{dbname}/_design/#{design_name}", nil, false
      design = res.json_value
      index = design.fulltext[index_name] if design["fulltext"]
      indexfun = index && index["index"]
      new_indexfun = edittext!(indexfun ||
        "function(doc) {\n  var ret = Document.new();\n\n  return ret;\n}\n")
      @ftitext = new_indexfun
      if new_indexfun == indexfun
        shell.msg "Index function hasn't changed. Nothing to submit."
        return
      end
      continue? "Press ENTER to submit #{indexfun ? 'updated' : 'new'} " +
                "index function, CTRL+C to cancel "
      if design["fulltext"].nil?
        design.set_attr!("fulltext", {})
      end
      if index.nil?
        design.fulltext.set_attr!(index_name, {})
        index = design.fulltext[index_name]
      end
      index.set_attr!("index", new_indexfun)
      unless shell.request("PUT", "/#{dbname}/_design/#{design_name}", design.to_s).ok?
        shell.msg "recover index text with `print ftitext'"
      end
    end

  end

end
