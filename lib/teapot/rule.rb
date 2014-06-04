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

module Teapot
	# A rule is a function with a specific set of input and output parameters, which can match against a given set of specific inputs and outputs. For example, there might be several rules for compiling, but the specific rules depend on the language being compiled.
	class Rule
		class Parameter
			def initialize(direction, name, options = {}, &block)
				@direction = direction
				@name = name
				
				@options = options
				
				@dynamic = block_given? ? Proc.new(&block) : nil
			end
			
			attr :direction
			attr :name
			
			attr :options
			
			def dynamic?
				@dynamic != nil
			end
			
			def applicable? arguments
				return false unless @options[:optional] or arguments.include?(@name)
				
				value = arguments[@name]
				
				return true if value == nil and @options[:optional]
				
				if pattern = @options[:pattern]
					case value
					when Array
						return false unless @options[:multiple]
						
						return value.all? {|item| pattern.match(item)}
					else
						return pattern.match(value)
					end
				end
				
				return true
			end
			
			def compute(arguments)
				if @dynamic
					@dynamic.call(arguments[@name], arguments)
				else
					arguments[@name]
				end
			end
			
			def inspect
				"#{direction}:#{@name} (#{options.inspect})"
			end
		end
		
		def initialize(process_name, type)
			@name = process_name + "." + type
			@full_name = @name.gsub(/[^\w]/, '_')
			
			@process_name = process_name.gsub('-', '_').to_sym
			@type = type
			
			@apply = nil
			
			@parameters = []
		end
		
		attr :process_name
		attr :full_name
		
		attr :primary_output
		
		def input(name, options = {}, &block)
			@parameters << Parameter.new(:input, name, options, &block)
		end
		
		def output(name, options = {}, &block)
			@parameters << Parameter.new(:output, name, options, &block)
			
			@primary_output ||= @parameters.last
		end
		
		# Check if this rule can process these parameters
		def applicable?(arguments)
			@parameters.each do |parameter|
				return false unless parameter.applicable?(arguments)
			end
			
			return true
		end
		
		def normalize(arguments)
			Hash[
				@parameters.collect do |parameter|
					[parameter.name, parameter.compute(arguments)]
				end
			]
		end
		
		def files(arguments)
			input_files = FSO::Files::Composite.new
			output_files = FSO::Files::Composite.new
			
			@parameters.each do |parameter|
				# This could probably be improved a bit, we are assuming all parameters are file based:
				files = arguments[parameter.name]
				
				next unless files
				
				case parameter.direction
				when :input
					input_files.merge(files)
				when :output
					output_files.merge(files)
				end
			end
			
			return input_files, output_files
		end
		
		def apply(&block)
			@apply = Proc.new(&block)
		end
		
		def apply!(scope, arguments)
			scope.instance_exec(arguments, &@apply)
		end
		
		def result(arguments)
			arguments[@primary_output.name]
		end
		
		def to_s
			"<#{self.class.name} #{@name.dump}>"
		end
	end
	
	class NoApplicableRule < StandardError
		def initialize(arguments)
			super "No applicable rule for parameters: #{arguments.inspect}"
			
			@arguments = arguments
		end
	end
end
