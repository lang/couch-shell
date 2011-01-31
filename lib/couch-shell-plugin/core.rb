# -*- encoding: utf-8 -*-

require "couch-shell/plugin"

module CouchShell

  class CorePlugin < Plugin

    var "A fresh uuid from the CouchDB server."
    def lookup_uuid
      shell.execute "uuids"
      if shell.responses.current(&:ok?)
        json = shell.responses.current.json_value
        if json && (uuids = json["uuids"]) && uuids.array? && uuids.length > 0
          uuids[0]
        else
          raise ShellError, "unkown json structure"
        end
      else
        raise ShellError, "uuids request failed"
      end
    end

    var "Value of the id or _id member of the last response."
    def lookup_id
      shell.responses.current { |r| r.attr "id", "_id" } or raise VarNotSet
    end

    var "Value of the rev or _rev member of the last response."
    def lookup_rev
      @responses.current { |r| r.attr "rev", "_rev" } or raise VarNotSet
    end

    var "Shortcut for $(id)?rev=$(rev)."
    def lookup_idr
      shell.interpolate "$(id)?rev=$(rev)"
    end

    var "Content-Type of the last response."
    def lookup_content_type
      shell.responses.current(&:content_type)
    end

    var "Current server url."
    def lookup_server
      raise VarNotSet unless shell.server_url
      u = shell.server_url
      "#{u.scheme}://#{u.host}:#{u.port}#{u.path}"
    end

    var "Get response with index X."
    def lookup_prefix_r(name)
      i = name.to_i
      raise VarNotSet unless shell.responses.readable_index?(i)
      shell.responses[i]
    end

    var "Get json of response with index X."
    def lookup_prefix_j(name)
      i = name.to_i
      if shell.responses.readable_index?(i)
        if shell.responses[i].json_value
          shell.responses[i].json_value
        else
          raise ShellError, "no json in response #{i}"
        end
      else
        raise ShellError, "no response index #{i}"
      end
    end

    def request_command_with_body(method, argstr)
      if argstr =~ CouchShell::JSON_DOC_START_RX
        url, bodyarg = nil, argstr
      else
        url, bodyarg= argstr.split(/\s+/, 2)
      end
      if bodyarg && bodyarg.start_with?("@")
        filename, content_type = bodyarg[1..-1].split(/\s+/, 2)
        body = CouchShell::FileToUpload.new(filename, content_type)
      else
        body = bodyarg
      end
      real_url = shell.interpolate(url)
      shell.request method, real_url, body
      real_url
    end

    cmd "Perform a GET http request.", synopsis: "[URL]"
    def execute_get(argstr)
      shell.request "GET", shell.interpolate(argstr)
    end

    cmd "Perform a PUT http request.",
      synopsis: "[URL] [JSON|@FILENAME]"
    def execute_put(argstr)
      request_command_with_body("PUT", argstr)
    end

    cmd "put, followed by cd if put was successful"
    def execute_cput(argstr)
      url = request_command_with_body("PUT", argstr)
      shell.cd url if shell.responses.current(&:ok?)
    end

    cmd "Perform a POST http request.",
      synopsis: "[URL] [JSON|@FILENAME]"
    def execute_post(argstr)
      request_command_with_body("POST", argstr)
    end

    cmd "Perform a DELETE http request.", synopsis: "[URL]"
    def execute_delete(argstr)
      shell.request "DELETE", shell.interpolate(argstr)
    end

    cmd "Change current path which will be used to interpret relative urls.",
      synopsis: "[PATH]"
    def execute_cd(argstr)
      shell.cd shell.interpolate(argstr), false
    end

    cmd "cd followed by get",
      synopsis: "[PATH]"
    def execute_cg(argstr)
      shell.cd shell.interpolate(argstr), true
    end

    cmd "quit shell"
    def execute_exit(argstr)
      raise Quit
    end

    cmd "quit shell"
    def execute_quit(argstr)
      raise Quit
    end

    cmd "Request uuid(s) from CouchDB server.",
      synopsis: "[COUNT]"
    def execute_uuids(argstr)
      count = argstr ? argstr.to_i : 1
      shell.request "GET", "/_uuids?count=#{count}"
    end

    cmd "Echos ARG after interpolating $(...) expressions.",
      synopsis: "[ARG]"
    def execute_echo(argstr)
      if argstr
        shell.stdout.puts shell.interpolate(argstr)
      end
    end

    cmd "Evaluate EXPR and print the result in a compact form.",
      synopsis: "EXPR"
    def execute_print(argstr)
      raise ShellError, "expression required" unless argstr
      shell.stdout.puts shell.eval_expr(argstr)
    end

    cmd "Evaluate EXPR and print the result in a pretty form.",
      synopsis: "EXPR"
    def execute_format(argstr)
      raise ShellError, "expression required" unless argstr
      val = shell.eval_expr(argstr)
      if val.respond_to?(:couch_shell_format_string!)
        shell.stdout.puts val.couch_shell_format_string!
      else
        shell.stdout.puts val
      end
    end

    cmd "Set URL of CouchDB server.",
      synopsis: "[URL]"
    def execute_server(argstr)
      shell.server = argstr
    end

    cmd "Show full url for PATH after interpolation.",
      synopsis: "[PATH]"
    def execute_expand(argstr)
      shell.stdout.puts shell.expand(shell.interpolate(argstr))
    end

    cmd "Execute COMMAND in your operating system's shell.",
      synopsis: "COMMAND"
    def execute_sh(argstr)
      raise ShellError, "argument required" unless argstr
      unless system(argstr)
        shell.errmsg "command exited with status #{$?.exitstatus}"
      end
    end

    cmd "Set member KEY of document at current path to VALUE.",
      synopsis: "KEY VALUE"
    def execute_member(argstr)
      id, rev = nil, nil
      json = shell.responses.current(&:json_value)
      unless json && (id = json.attr_or_nil!("_id")) &&
          (rev = json.attr_or_nil!("_rev")) &&
          (shell.pathstack.size > 0) &&
          (shell.pathstack.last == id.to_s)
        raise ShellError,
          "`cg' the desired document first, e.g.: `cg /my_db/my_doc_id'"
      end
      # TODO: read json string as attribute name if argstr starts with double
      # quote
      attr_name, new_valstr = argstr.split(/\s+/, 2)
      unless attr_name && new_valstr
        raise ShellError,
          "attribute name and new value argument required"
      end
      if new_valstr == "remove"
        json.delete_attr!(attr_name)
      else
        new_val = JsonValue.parse(new_valstr)
        json.set_attr!(attr_name, new_val)
      end
      shell.request "PUT", "?rev=#{rev}", json.to_s
    end

    cmd "Set the USERNAME and password for authentication in requests.",
      synopsis: "USERNAME",
      doc_text: "Prompts for password."
    def execute_user(argstr)
      shell.prompt_msg("Password:", false)
      shell.password = shell.read_secret
      # we save the username only after the password was entered
      # to allow cancellation during password input
      shell.username = argstr
    end

    cmd "Use PLUGIN.",
      synopsis: "PLUGIN"
    def execute_plugin(argstr)
      shell.plugin argstr
    end

  end

end
