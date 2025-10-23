require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

# Add lib to load path
LIB_DIR = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(LIB_DIR) unless $LOAD_PATH.include?(LIB_DIR)

require 'shortbus'

class ShortbusTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_root = Shortbus.root
    Shortbus.root = @tmpdir

    # Create necessary subdirectories
    FileUtils.mkdir_p(File.join(@tmpdir, 'config'))
    FileUtils.mkdir_p(File.join(@tmpdir, 'topics'))
    FileUtils.mkdir_p(File.join(@tmpdir, 'logs'))
  end

  def teardown
    Shortbus.root = @original_root
    FileUtils.rm_rf(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
  end

  def rendezvous_path(*parts)
    File.join(@tmpdir, *parts)
  end
end
