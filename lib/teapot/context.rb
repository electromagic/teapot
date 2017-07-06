# Copyright, 2012, by Samuel G. D. Williams. <http://www.codeotaku.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require_relative 'loader'
require_relative 'package'

require 'build/rulebook'
require 'build/text/substitutions'
require 'build/text/merge'

module Teapot
	TEAPOT_FILE = 'teapot.rb'.freeze
	DEFAULT_CONFIGURATION_NAME = 'default'.freeze

	class AlreadyDefinedError < StandardError
		def initialize(definition, previous)
			super "Definition #{definition.name} in #{definition.path} has already been defined in #{previous.path}!"
		end

		def self.check(definition, definitions)
			previous = definitions[definition.name]

			raise self.new(definition, previous) if previous
		end
	end

	# A context represents a specific root package instance with a given configuration and all related definitions.
	# A context is stateful in the sense that package selection is specialized based on #select and #dependency_chain. These parameters are usually set up initially as part of the context setup.
	class Context
		def initialize(root, options = {})
			@root = Path[root]
			@options = options

			@targets = {}
			@configurations = {}
			@projects = {}
			@rules = Build::Rulebook.new

			@dependencies = []
			@selection = Set.new

			@loaded = {}

			unless options[:fake]
				load_root_package(options)
			end
		end

		attr :root
		attr :options

		attr :targets
		attr :projects

		# Context metadata
		attr :metadata

		# All public configurations.
		attr :configurations

		attr :rules

		# The context's primary configuration.
		attr :configuration

		# The context's primary project.
		attr :project

		attr :dependencies
		attr :selection

		def repository
			@repository ||= Rugged::Repository.new(@root.to_s)
		end

		def substitutions
			substitutions = Build::Text::Substitutions.new

			if @project
				substitutions['PROJECT_NAME'] = @project.name
				substitutions['LICENSE'] = @project.license
			end

			# The user's current name:
			substitutions['AUTHOR_NAME'] = repository.config['user.name']
			substitutions['AUTHOR_EMAIL'] = repository.config['user.email']

			current_date = Time.new
			substitutions['DATE'] = current_date.strftime("%-d/%-m/%Y")
			substitutions['YEAR'] = current_date.strftime("%Y")

			return substitutions
		end

		def select(names)
			names.each do |name|
				if @targets.key? name
					@selection << name
				else
					@dependencies << name
				end
			end
		end

		def dependency_chain(dependency_names, configuration = @configuration)
			configuration.load_all
			
			select(dependency_names)
			
			Build::Dependency::Chain.expand(@dependencies, @targets.values, @selection)
		end

		def direct_targets(ordered)
			@dependencies.collect do |dependency|
				ordered.find{|(package, _)| package.provides? dependency}
			end.compact
		end

		# Add a definition to the current context.
		def << definition
			case definition
			when Target
				AlreadyDefinedError.check(definition, @targets)

				@targets[definition.name] = definition
			when Configuration
				# We define configurations in two cases, if they are public, or if they are part of the root package of this context.
				if definition.public? or definition.package == @root_package
					# The root package implicitly defines the default configuration.
					if definition.name == DEFAULT_CONFIGURATION_NAME
						raise AlreadyDefinedError.new(definition, root_package)
					end

					AlreadyDefinedError.check(definition, @configurations)

					@configurations[definition.name] = definition
				end
			when Project
				AlreadyDefinedError.check(definition, @projects)

				@project ||= definition

				@projects[definition.name] = definition
			when Rule
				AlreadyDefinedError.check(definition, @rules)

				@rules << definition
			end
		end

		def load(package)
			# In certain cases, a package record might be loaded twice. This typically occurs when multiple configurations are loaded in the same context, or if a package has already been loaded (as is typical with the root package).
			@loaded.fetch(package) do
				loader = Loader.new(self, package)
				
				loader.load(TEAPOT_FILE)
				
				# Load the definitions into the current context:
				loader.defined.each do |definition|
					self << definition
				end

				# Save the definitions per-package:
				@loaded[package] = loader.defined
			end
		end

		def unresolved(packages)
			failed_to_load = Set.new
			
			packages.collect do |package|
				begin
					definitions = load(package)
				rescue NonexistantTeapotError, IncompatibleTeapotError
					# If the package doesn't exist or the teapot version is too old, it failed:
					failed_to_load << package
				end
			end
			
			return failed_to_load
		end
		
		# The root package is a special package which is used to load definitions from a given root path.
		def root_package
			@root_package ||= Package.new(@root, "root")
		end
		
		private
		
		def load_root_package(options)
			# Load the root package:
			defined = load(root_package)

			# Find the default configuration, if it exists:
			@default_configuration = defined.default_configuration

			if configuration_name = options[:configuration]
				@configuration = @configurations[configuration_name]
			else
				@configuration = @default_configuration
			end
			
			if @configuration.nil?
				raise ArgumentError.new("Could not load configuration: #{configuration_name.inspect}")
			end
			
			# Materialize the configuration:
			@configuration.materialize if @configuration
		end
	end
end
