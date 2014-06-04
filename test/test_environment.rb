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

require "minitest/autorun"

require 'teapot/environment'

class TestEnvironment < MiniTest::Test
	def test_environment_chaining
		a = Teapot::Environment.new
		a[:cflags] = ["-std=c++11"]
		
		b = Teapot::Environment.new(a, {})
		b[:cflags] = ["-stdlib=libc++"]
		b[:rcflags] = lambda {cflags.reverse}
		
		expected = {:cflags => ["-std=c++11", "-stdlib=libc++"], :rcflags => ["-stdlib=libc++", "-std=c++11"]}
		
		assert_equal expected, b.flatten.to_hash
	end
	
	def test_environment_lambda
		a = Teapot::Environment.new do
			sdk "bob-2.6"
			cflags [->{"-sdk=#{sdk}"}]
		end
		
		b = Teapot::Environment.new(a) do
			sdk "bob-2.8"
		end
		
		c = Teapot::Environment.new(b) do
			cflags ["-pipe"]
		end
		
		expected = {'SDK' => "bob-2.8", 'CFLAGS' => "-sdk=bob-2.8"}
		
		assert_equal [:cflags, :sdk], b.flatten.to_hash.keys.sort
		assert_equal expected, Teapot::Environment::System::convert_to_shell(b.flatten)
		
		assert_equal %W{-sdk=bob-2.8 -pipe}, c.flatten[:cflags]
	end
	
	def test_environment_nested_lambda
		a = Teapot::Environment.new do
			sdk "bob-2.6"
			cflags [->{"-sdk=#{sdk}"}]
		end
		
		b = Teapot::Environment.new(a) do
			sdk "bob-2.8"
		end
	end
	
	def test_combine
		a = Teapot::Environment.new(nil, {:name => 'a'})
		b = Teapot::Environment.new(a, {:name => 'b'})
		c = Teapot::Environment.new(nil, {:name => 'c'})
		d = Teapot::Environment.new(c, {:name => 'd'})

		top = Teapot::Environment.combine(b, d)
		
		assert_equal d.values, top.values
		assert_equal c.values, top.parent.values
		assert_equal b.values, top.parent.parent.values
		assert_equal a.values, top.parent.parent.parent.values
	end
	
	def test_combine_defaults
		local = Teapot::Environment.new do
			architectures ["-m64"]
		end
		
		platform = Teapot::Environment.new do
			default architectures ["-arch", "i386"]
		end
		
		combined = Teapot::Environment.combine(
			platform,
			local
		)
		
		assert_equal ["-m64"], combined[:architectures]
	end
end
