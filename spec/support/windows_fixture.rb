require 'spec_helper'

module WindowsFixture
  def start_fixture
    # RSpec command-line tags can override configured exclusions.
    raise 'Live desktop scenarios require Windows and BLINDLY4_LIVE=1' unless Blindly::WINDOWS && ENV['BLINDLY4_LIVE'] == '1'

    @fixture_pid = Process.spawn([Blindly::BINARY, Blindly::BINARY], '--test-app',
                                 in: File::NULL, out: File::NULL, err: File::NULL)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      frontmost = success('apps').fetch('apps').any? { |app| app.fetch('pid') == @fixture_pid && app.fetch('frontmost') }
      if frontmost
        ready = cli('find', '--pid', @fixture_pid, '--title', 'Fixture ready', '--role', 'AXStaticText', '--limit', '1')
        break if ready.status == 0 && ready.json.fetch('matches').any? { |row| row.fetch('title') == 'Fixture ready' }
      end
      raise 'The fixture exited before opening' if Process.waitpid(@fixture_pid, Process::WNOHANG)
      raise 'The fixture was not ready in the foreground within 10 seconds' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.1
    end
  end

  def stop_fixture
    return unless @fixture_pid

    Process.kill('KILL', @fixture_pid)
    Process.waitpid(@fixture_pid)
  rescue Errno::ESRCH, Errno::ECHILD
    # The fixture may already have exited; never terminate any other process.
  ensure
    @fixture_pid = nil
  end

  def app(command, *arguments)
    success(command, '--pid', @fixture_pid, *arguments)
  end

  def rejected_app(status, command, *arguments)
    result = cli(command, '--pid', @fixture_pid, *arguments)
    expect(result.status).to eq(status), "#{command}: #{result.stdout}\n#{result.stderr}"
    code = status == 64 ? 'usage_error' : 'accessibility_error'
    expect(result.json).to include('code' => code, 'error' => a_string_matching(/\S/))
    result.json
  end

  # Resolve by the visible label every time; do not cache UI paths across actions.
  def control(title, role)
    matches = app('find', '--title', title, '--role', role, '--depth', '6').fetch('matches')
    expect(matches.length).to eq(1), "Expected one #{role} named #{title}, got #{matches.inspect}"
    matches.first.fetch('path')
  end

  def draft
    control('Draft', 'AXTextField')
  end

  def submit
    control('Submit test draft', 'AXButton')
  end

  def draft_value
    app('inspect', '--path', draft).fetch('value')
  end

  def set_draft(text)
    app('set-value', '--path', draft, '--value', text)
  end

  def expect_not_submitted
    expect(app('find', '--title', 'Not submitted').fetch('matches').length).to eq(1)
  end

  def field_value(title)
    app('inspect', '--path', control(title, 'AXTextField')).fetch('value')
  end

  def visible_label(prefix)
    app('find', '--title', prefix, '--role', 'AXStaticText').fetch('matches')
      .map { |row| row.fetch('title') }.find { |title| title.start_with?(prefix) }
  end

  # Poll observed UI state, never repeat the action under test.
  def observe_until(description = 'Expected desktop state')
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      observed = yield
      return if observed
      raise "#{description} was not observed within 5 seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.05
    end
  end

  def expect_label(text)
    observe_until("Visible label #{text.inspect}") { visible_label(text) == text }
  end

  def expect_untouched_neighbors
    expect(field_value('First field')).to eq('first untouched')
    expect(field_value('Third field')).to eq('third untouched')
  end
end

RSpec.shared_context 'a native Windows fixture' do
  include WindowsFixture

  around do |example|
    begin
      start_fixture
      example.run
      if example.exception
        # Read only this disposable fixture, to explain focus/draft failures.
        RSpec.configuration.reporter.message("Fixture focus: #{cli('focused', '--pid', @fixture_pid).stdout.strip}")
        RSpec.configuration.reporter.message("Fixture draft: #{cli('find', '--pid', @fixture_pid, '--title', 'Draft', '--role', 'AXTextField').stdout.strip}")
      end
    ensure
      stop_fixture
    end
  end
end
