# -*- encoding: utf-8 -*-

require "couch-shell/exceptions"

module CouchShell

  # Requires an instance method named "shell" that returns a
  # CouchShell::Shell compatible object.
  module PluginUtils

    class ShellError < ShellUserError
    end

    class VarNotSet < ShellError

      attr_accessor :var

      def message
        "Variable @#{@var.plugin.plugin_name}.#{@var.name} not set."
      end

    end

    # Get the first element of pathstack or raise an exception if pathstack is
    # empty.
    def dbname!
      raise ShellError, "must cd into database" if shell.pathstack.empty?
      shell.pathstack[0]
    end

    # Raise an exception unless pathstack size is 1.
    def ensure_at_database
      if shell.pathstack.size != 1
        raise ShellError, "current directory must be database"
      end
    end

    # Displays msg in the same style as the standard couch-shell prompt
    # and raises ShellError unless the user hits ENTER and nothing else.
    #
    # Usage:
    #   
    #   # do some setup logic
    #   continue?("Changes made: foo replaced by bar\n" +
    #             "Press ENTER to save changes or CTRL+C to cancel")
    #   # save changes
    def continue?(msg)
      shell.prompt_msg(msg, false)
      unless shell.stdin.gets.chomp.empty?
        raise ShellError, "cancelled"
      end
    end

    # Like shell.request, but raises a ShellError ("required request failed")
    # if response.ok? is false.
    def request!(*args)
      shell.request(*args).tap do |res|
        raise ShellError, "required request failed" unless res.ok?
      end
    end

    # Opens editor with the given file path and returns after the user closes
    # the editor or raises a ShellError if the editor doesn't exit with an exit
    # status of 0.
    def editfile!(path)
      unless system(shell.editor_bin!, path)
        raise ShellError, "editing command failed with exit status #{$?.exitstatus}"
      end
    end

    # Writes content to a temporary file, calls editfile! on it and returns the
    # new file content on success after unlinking the temporary file.
    def edittext!(content, tempfile_name_ext = ".js", tempfile_name_part = "cs")
      t = Tempfile.new([tempfile_name_part, tempfile_name_ext])
      t.write(content)
      t.close
      editfile! t.path
      t.open.read
    ensure
      if t
        t.close
        t.unlink
      end
    end

    def respond_to?(msg)
      super || shell.respond_to?(msg)
    end

    # Tries to delegate msg to shell.
    def method_missing(msg, *args)
      if shell.respond_to?(msg)
        shell.send msg, *args
      else
        super
      end
    end

  end

end
