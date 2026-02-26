# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

require 'rake/extensiontask'

desc 'Build the gem'
task build: :compile

GEMSPEC = Gem::Specification.load('chroma_wave.gemspec')

Rake::ExtensionTask.new('chroma_wave', GEMSPEC) do |ext|
  ext.lib_dir = 'lib/chroma_wave'
end

namespace :generate do
  desc 'Regenerate driver_configs_generated.h from vendor sources'
  task :driver_configs do
    require_relative 'lib/chroma_wave/driver_extraction'
    ChromaWave::DriverExtraction::Runner.new.call
  end
end

task default: %i[clobber compile spec rubocop]
