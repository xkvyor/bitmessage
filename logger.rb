# encoding: utf-8

class Logger
	def initialize(filepath=nil)
		if filepath
			@fd = open(filepath, 'a')
		else
			@fd = STDOUT
		end
		@level = "INFO"
	end

	def now
		Time.now.to_s
	end

	def debug(msg)
		@level = "DEBUG"
		log msg
	end

	def error(msg)
		@level = "ERROR"
		log msg
	end

	def warn(msg)
		@level = "WARN"
		log msg
	end

	def info(msg)
		@level = "INFO"
		log msg
	end

	def log(msg)
		@fd.puts "[#{now}] [#{@level}] #{msg}"
	end

	private :log
end
