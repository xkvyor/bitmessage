# encoding: utf-8

require 'singleton'
require './config'

class Logger
	include Singleton

	LEVELS = [:info, :debug, :warn, :error]

	def initialize
		@filepath = BMConfig::Log_file
		@level = BMConfig::Log_level
		if @filepath
			@fd = open(@filepath, 'a')
		else
			@fd = STDOUT
		end
		@type = "INFO"
	end

	def now
		Time.now.to_s
	end

	def debug(msg)
		@type = "DEBUG"
		log msg if level_test(:debug)
	end

	def error(msg)
		@type = "ERROR"
		log msg if level_test(:error)
	end

	def warn(msg)
		@type = "WARN"
		log msg if level_test(:warn)
	end

	def info(msg)
		@type = "INFO"
		log msg if level_test(:info)
	end

	def log(msg)
		@fd.puts "[#{now}] [#{@type}] #{msg}"
	end

	def level_test(method)
		m = LEVELS.index method
		l = LEVELS.index @level
		m >= l
	end

	private :log, :level_test
end

# l = Logger.instance
# l.info "hee"