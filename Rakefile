# encoding: utf-8

require "#{File.dirname(__FILE__)}/lib/couch-shell/version"

gem_filename = "couch-shell-#{CouchShell::VERSION}.gem"

task "default" => "test"

desc "Run unit tests."
task "test" do
  sh "ruby19 -I lib -I . test/suite.rb"
end

desc "Build couch-shell gem."
task "gem" do
  sh "gem19 build couch-shell.gemspec"
  mkdir "pkg" unless File.directory? "pkg"
  mv gem_filename, "pkg"
end

desc "Remove generated packages and documentation."
task "clean" do
  rm_r "pkg" if File.exist? "pkg"
end
