require_relative '../test_helper'

class BasicTest < ShortbusTest
  def test_version_defined
    assert Shortbus::VERSION
    assert_match /\d+\.\d+\.\d+/, Shortbus.version
  end

  def test_config_accessible
    assert Shortbus.config
    assert_kind_of Shortbus::Config, Shortbus.config
  end

  def test_root_configuration
    assert_equal @tmpdir, Shortbus.root
    assert_equal @tmpdir, Shortbus.config.root
  end

  def test_config_paths
    config = Shortbus.config

    assert_equal Pathname.new(@tmpdir), config.root_path
    assert_equal Pathname.new(File.join(@tmpdir, 'config')), config.config_dir
    assert_equal Pathname.new(File.join(@tmpdir, 'topics')), config.topics_dir
    assert_equal Pathname.new(File.join(@tmpdir, 'logs')), config.logs_dir
  end

  def test_pid_file_path
    expected = File.join(@tmpdir, 'shortbus.pid')
    assert_equal Pathname.new(expected), Shortbus.config.pid_file
  end

  def test_socket_path
    expected = File.join(@tmpdir, 'shortbus.sock')
    assert_equal Pathname.new(expected), Shortbus.config.socket_path
  end
end
