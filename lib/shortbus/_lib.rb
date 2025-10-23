module Shortbus
  class << self
    def libs
      %w[
        socket fileutils pathname yaml json logger uri net/http time date thread securerandom
      ]
    end

    def dependencies
      {
        'map' => ['map', '~> 6.6', '>= 6.6.0'],
        'listen' => ['listen', '~> 3.8'],
      }
    end

    def libdir(*args, &block)
      @libdir ||= File.dirname(File.expand_path(__FILE__))
      args.empty? ? @libdir : File.join(@libdir, *args)
    ensure
      if block
        begin
          $LOAD_PATH.unshift(@libdir)
          block.call
        ensure
          $LOAD_PATH.shift
        end
      end
    end

    def load(*libs)
      libs = libs.join(' ').scan(/[^\s+]+/)
      libdir { libs.each { |lib| Kernel.load(lib) } }
    end

    def load_dependencies!
      libs.each do |lib|
        require lib
      end

      begin
        require 'rubygems'
      rescue LoadError
        nil
      end

      has_rubygems = defined?(gem)

      dependencies.each do |lib, dependency|
        gem(*dependency) if has_rubygems
        require(lib)
      end
    end
  end
end
