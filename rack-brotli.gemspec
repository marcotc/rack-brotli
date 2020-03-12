begin
	require 'git-version-bump'
rescue LoadError
	nil
end

Gem::Specification.new do |s|
  s.specification_version = 2 if s.respond_to? :specification_version=
  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=

  s.name    = 'rack-brotli'
  s.version = GVB.version rescue "0.0.0"
  s.date    = GVB.date    rescue Time.now.strftime("%F")

  s.licenses = ['MIT']

  s.description = "Rack::Brotli enables Google's Brotli compression on HTTP responses"
  s.summary     = "Brotli compression for Rack responses"

  s.authors = ["Marco Costa"]
  s.email = "marco@marcotc.com"

  # = MANIFEST =
  s.files = %w[
    COPYING
    README.md
  ] + `git ls-files -z lib`.split("\0")

  s.test_files = s.files.select {|path| path =~ /^test\/.*\_spec.rb/}

  s.extra_rdoc_files = %w[README.md COPYING]

  s.add_runtime_dependency 'rack', '>= 1.4'
  s.add_runtime_dependency 'git-version-bump', '>= 0.15'
  s.add_runtime_dependency 'brotli', '>= 0.1.7'

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'github-release', '~> 0.1'
  s.add_development_dependency 'minitest', '~> 5.6'
  s.add_development_dependency 'rake', '~> 12', '>= 12.3.3'
  s.add_development_dependency 'rdoc', '~> 3.12'

  s.has_rdoc = true
  s.homepage = "http://github.com/marcotc/rack-brotli/"
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "rack-brotli", "--main", "README"]
  s.require_paths = %w[lib]
  s.rubygems_version = '0.1.0'
end
