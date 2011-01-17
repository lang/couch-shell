# encoding: utf-8

require "#{File.dirname(__FILE__)}/lib/couch-shell/version"

files = Dir["lib/**/*.rb"] +
  ["bin/couch-shell", "README.txt", "LICENSE.txt"]
files.reject! { |fn| fn.end_with?("~") }

Gem::Specification.new do |g|
  g.name = "couch-shell"
  g.version = CouchShell::VERSION
  g.platform = Gem::Platform::RUBY
  g.summary = "A shell to interact with a CouchDB server."
  g.files = files
  g.require_paths = ["lib"]
  g.bindir = "bin"
  g.executables = ["couch-shell"]
  g.test_files = []
  #g.required_ruby_version = ">= 1.9.1"
  g.author = "Stefan Lang"
  g.email = "langstefan@gmx.at"
  g.has_rdoc = false
  #g.extra_rdoc_files = ["README.txt", "INSTALL.txt"]
  #g.rdoc_options = ["--main=README.txt", "--charset=UTF-8"]
  g.homepage = "http://github.com/lang/couch-shell"
  #g.rubyforge_project = "unicode-utils"
end
