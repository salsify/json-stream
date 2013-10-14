require 'rake'
require 'rake/clean'
require 'rubygems/package_task'
require 'rake/testtask'
require_relative 'lib/json/stream/version'

spec = Gem::Specification.new do |s|
  s.name    = "json-stream"
  s.version = JSON::Stream::VERSION
  s.date    = Time.now.strftime("%Y-%m-%d")

  s.summary     = "A streaming JSON parser that generates SAX-like events."
  s.description = "A finite state machine based JSON parser that generates events
for each state change. This allows us to stream both the JSON document into
memory and the parsed object graph out of memory to some other process. This
is much like an XML SAX parser that generates events during parsing. There is
no requirement for the document nor the object graph to be fully buffered in
memory. This is best suited for huge JSON documents that won't fit in memory.
For example, streaming and processing large map/reduce views from Apache CouchDB."

  s.authors      = ["David Graham"]
  s.email        = ["david.malcom.graham@gmail.com"]
  s.homepage     = "http://dgraham.github.com/json-stream/"

  s.files        = FileList['[A-Z]*', "{lib}/**/*"]
  s.test_files   = FileList["{test}/**/*test.rb"]
  s.require_path = "lib"

  s.add_development_dependency "rake"
  s.required_ruby_version = '>= 1.9.2'
end

Gem::PackageTask.new(spec) do |pkg|
  pkg.need_tar = true
end

Rake::TestTask.new(:test) do |test|
  test.pattern = 'test/**/*_test.rb'
  test.warning = true
end

task :default => [:clobber, :test, :gem]
