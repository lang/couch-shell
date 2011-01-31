# -*- encoding: utf-8 -*-

require "couch-shell/plugin"

module CouchShell

  class CoreViewsPlugin < Plugin

    def plugin_initialization
      @viewtext = nil
    end

    var "Text saved by the last invocation of editview."
    def lookup_viewtext
      @viewtext or raise VarNotSet
    end

    cmd "Edit map, and optionally reduce function in your editor.",
      synopsis: "DESIGN VIEW"
    def execute_editview(argstr)
      ensure_at_database
      design_name, view_name = argstr.split(/\s+/, 2)
      if design_name.nil? || view_name.nil?
        raise ShellError, "design and view name required"
      end
      shell.request "GET", "_design/#{design_name}", nil, false
      return unless shell.responses.current(&:ok?)
      design = shell.responses.current.json_value
      view = design.views[view_name] if design["views"]
      mapval = view && view["map"]
      reduceval = view && view["reduce"]
      t = Tempfile.new(["view", ".js"])
      t.puts("map")
      if mapval
        t.puts mapval
      else
        t.puts "function(doc) {\n  emit(doc._id, doc);\n}"
      end
      if reduceval || view.nil?
        t.puts
        t.puts("reduce")
        if reduceval
          t.puts reduceval
        else
          t.puts "function(keys, values, rereduce) {\n\n}"
        end
      end
      t.close
      continue?("Press ENTER to edit #{view ? 'existing' : 'new'} view, " +
                "CTRL+C to cancel ")
      unless system(shell.editor_bin!, t.path)
        raise ShellError, "editing command failed with exit status #{$?.exitstatus}"
      end
      text = t.open.read
      @viewtext = text
      t.close
      mapf = nil
      reducef = nil
      inmap = false
      inreduce = false
      i = 0
      text.each_line { |line|
        i += 1
        case line
        when /^map\s*(.*)$/
          unless $1.empty?
            shell.msg "recover view text with `print viewtext'"
            raise ShellError, "invalid map line at line #{i}"
          end
          unless mapf.nil?
            shell.msg "recover view text with `print viewtext'"
            raise ShellError, "duplicate map line at line #{i}"
          end
          inreduce = false
          inmap = true
          mapf = ""
        when /^reduce\s*(.*)$/
          unless $1.empty?
            shell.msg "recover view text with `print viewtext'"
            raise ShellError, "invalid reduce line at line #{i}"
          end
          unless reducef.nil?
            shell.msg "recover view text with `print viewtext'"
            raise ShellError, "duplicate reduce line at line #{i}"
          end
          inmap = false
          inreduce = true
          reducef = ""
        else
          if inmap
            mapf << line
          elsif inreduce
            reducef << line
          elsif line =~ /^\s*$/
            # ignore
          else
            shell.msg "recover view text with `print viewtext'"
            raise ShellError, "unexpected content at line #{i}"
          end
        end
      }
      mapf.strip! if mapf
      reducef.strip! if reducef
      mapf = nil if mapf && mapf.empty?
      reducef = nil if reducef && reducef.empty?
      shell.prompt_msg "View parsed, following actions would be taken:"
      if mapf && mapval.nil?
        shell.prompt_msg " Add map function."
      elsif mapf.nil? && mapval
        shell.prompt_msg " Remove map function."
      elsif mapf && mapval && mapf != mapval
        shell.prompt_msg " Update map function."
      end
      if reducef && reduceval.nil?
        shell.prompt_msg " Add reduce function."
      elsif reducef.nil? && reduceval
        shell.prompt_msg " Remove reduce function."
      elsif reducef && reduceval && reducef != reduceval
        shell.prompt_msg " Update reduce function."
      end
      continue? "Press ENTER to submit, CTRL+C to cancel "
      if !design.respond_to?(:views)
        design.set_attr!("views", {})
      end
      if view.nil?
        design.views.set_attr!(view_name, {})
        view = design.views[view_name]
      end
      if mapf.nil?
        view.delete_attr!("map")
      else
        view.set_attr!("map", mapf)
      end
      if reducef.nil?
        view.delete_attr!("reduce")
      else
        view.set_attr!("reduce", reducef)
      end
      shell.request "PUT", "_design/#{design_name}", design.to_s
      unless shell.responses.current(&:ok?)
        shell.msg "recover view text with `print viewtext'"
      end
    ensure
      if t
        t.close
        t.unlink
      end
    end

    cmd "Shortcut to GET a view.",
      synopsis: "DESIGN/VIEW[?params]"
    def execute_view(argstr)
      if shell.pathstack.size != 1
        raise ShellError, "current directory must be database"
      end
      design_name, view_name = argstr.split("/", 2)
      if design_name.nil? || view_name.nil?
        raise ShellError, "argument in the form DESIGN/VIEW required"
      end
      shell.request "GET", "_design/#{design_name}/_view/#{view_name}"
    end

  end

end
