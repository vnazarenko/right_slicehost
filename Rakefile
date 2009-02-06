# -*- ruby -*-

require 'rubygems'
require 'hoe'
require './lib/right_slicehost.rb'

Hoe.new('right_slicehost', RightSlicehost::VERSION) do |p|
  p.rubyforge_name = 'rightslicehost'
  p.author = 'RightScale, Inc.'
  p.email = 'support@rightscale.com'
  p.summary = 'Interface classes for the Slicehost API'
  p.description = p.paragraphs_of('README.txt', 2..5).join("\n\n")
  p.url = p.paragraphs_of('README.txt', 0).first.split(/\n/)[1..-1]
  p.changes = p.paragraphs_of('History.txt', 0..1).join("\n\n")
  p.remote_rdoc_dir = "/right_slicehost_gem_doc"
  p.extra_deps = [['right_http_connection','>= 1.2.1']]
end

# vim: syntax=Ruby
