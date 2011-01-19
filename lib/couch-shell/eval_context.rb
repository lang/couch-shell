# -*- encoding: utf-8 -*-

module CouchShell

  class EvalContext < BasicObject

    def initialize(vardict)
      @vardict = vardict
    end

    def method_missing(msg, *args)
      if args.empty?
        @vardict.lookup_var msg.to_s
      else
        super
      end
    end

  end

end
