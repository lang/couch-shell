# -*- encoding: utf-8 -*-

require "couch-shell/exceptions"

module CouchShell

  class EvalContext < BasicObject

    # weird trickery ahead
    # we want only instance_variable_set from kernel
    include ::Kernel
    alias_method :_instance_variable_set, :instance_variable_set
    (::Kernel.instance_methods + ::Kernel.private_instance_methods).each { |m|
      # Ruby 1.9.2p0 prints a warning when undefining object_id,
      # although BasicObject doesn't define it anyway, making this
      # warning obsolete IMHO.
      if m == :object_id
        oldv = $VERBOSE
        begin
          $VERBOSE = nil
          undef_method m
        ensure
          $VERBOSE = oldv
        end
      else
        undef_method m
      end
    }

    def initialize(vardict)
      @_vardict = vardict
    end

    def method_missing(msg, *args)
      if args.empty?
        @_vardict.lookup_var msg.to_s
      else
        raise ShellUserError, "unexpected syntax at #{msg}"
      end
    end

  end

end
