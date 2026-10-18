require 'json'
require 'open3'
require 'timeout'
require 'rspec/expectations'

module Blindly
  ROOT = File.expand_path('..', __dir__)
  WINDOWS = Gem.win_platform?
  BINARY = File.expand_path(ENV.fetch('BLINDLY4_BIN', WINDOWS ? '.build/windows/blindly4.exe' : '.build/debug/blindly4'), ROOT)
  COMMANDS = %w[schema request-permission apps activate open tree show find focused inspect actions focus press show-menu scroll-to set-value set-selected-text click type paste scroll key].freeze
  Result = Struct.new(:stdout, :stderr, :status) do
    def json
      JSON.parse(stdout)
    end
  end

  def cli(*arguments)
    # An argv array preserves Unicode and empty strings without involving a shell.
    Open3.popen3([BINARY, BINARY], *arguments.map(&:to_s), chdir: ROOT) do |input, output, error, child|
      input.close
      readers = [output, error].map { |stream| Thread.new { stream.read.force_encoding(Encoding::UTF_8) } }
      begin
        Timeout.timeout(30) do
          stdout, stderr = readers.map(&:value)
          Result.new(stdout, stderr, child.value.exitstatus)
        end
      ensure
        if child.alive?
          Process.kill('KILL', child.pid)
          child.join
        end
        readers.each(&:join)
      end
    end
  end

  def success(*arguments)
    result = cli(*arguments)
    expect(result.status).to eq(0), "#{arguments.inspect}: exit #{result.status}\n#{result.stdout}\n#{result.stderr}"
    expect(result.stderr).to eq('')
    result.json
  end

  def usage_error(*arguments)
    result = cli(*arguments)
    expect(result.status).to eq(64), "#{arguments.inspect}: exit #{result.status}\n#{result.stdout}\n#{result.stderr}"
    if WINDOWS
      expect(result.json).to include('code' => 'usage_error', 'error' => a_string_matching(/\S/))
    else
      # The existing macOS usage contract is human-readable stderr.
      expect(result.stdout).to eq('')
      expect(result.stderr).to match(/\S/)
    end
    result
  end
end

RSpec.configure do |config|
  config.fail_if_no_examples = true
  config.include Blindly
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.filter_run_excluding windows: true unless Blindly::WINDOWS
  config.filter_run_excluding live: true unless ENV['BLINDLY4_LIVE'] == '1'
  config.before(:suite) do
    raise "Build blindly4 first or set BLINDLY4_BIN: #{Blindly::BINARY}" unless File.file?(Blindly::BINARY)
    raise 'The live fixture requires an interactive Windows desktop' if ENV['BLINDLY4_LIVE'] == '1' && !Blindly::WINDOWS
  end
end
