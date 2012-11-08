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

require 'pathname'

module Teapot
	class BuildError < StandardError
	end
	
	class Task
		def initialize
			@callbacks = {}
		end
			
		def define(name, &callback)
			@callbacks[name] = callback
		end
			
		def [](name)
			@callbacks[name] || @callbacks[:all]
		end
	end
	
	class Package
		def initialize(context, record, name)
			@context = context
			@record = record

			parts = name.split('-')
			@name = parts[0..-2].join('-')
			@version = parts[-1]

			@build = Task.new

			@depends = []

			@path = @record.destination_path
			@source_path = @path + name
		end

		attr :context
		attr :record
		
		attr :name
		attr :version
		
		attr :path

		attr :depends, true
		attr :source_path, true

		def build(platform, &block)
			@build.define(platform, &block)
		end

		def build!(platform = :all, config = {})
			task = @build[platform.name]
			
			if task
				environment = Environment.combine(
					@record.options[:environment],
					platform.environment,
					config,
				)
				
				Dir.chdir(@path) do
					task.call(platform, environment)
				end
			else
				raise BuildError.new("Could not find build task for #{platform.name}!")
			end
		end

		def to_s
			"<Package: #{@name}>"
		end

		def self.build_order(available, packages)
			ordered = []

			expand = lambda do |name|
				package = available[name]

				unless package
					puts "Couldn't resolve #{name}"
				else
					package.depends.each do |dependency|
						expand.call(dependency)
					end

					unless ordered.include? package
						ordered << package
					end
				end
			end

			packages.each do |package|
				expand.call(package.name)
			end

			return ordered
		end
	end
end
