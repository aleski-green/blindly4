require 'spec_helper'

module DesktopFixture
  def start_fixture_with_live_opt_in
    raise 'Live desktop scenarios require BLINDLY4_LIVE=1' unless ENV['BLINDLY4_LIVE'] == '1'

    metadata = RSpec.current_example.metadata
    @fixture_pid = Process.spawn({ 'BLINDLY4_FIXTURE_VALUE' => metadata[:value_mode],
                                  'BLINDLY4_FIXTURE_ROLE' => metadata[:discovery_role],
                                  'BLINDLY4_FIXTURE_PASTE' => metadata[:paste_mode],
                                  'BLINDLY4_FIXTURE_CHILD' => metadata[:child_process] ? '1' : nil,
                                  'BLINDLY4_FIXTURE_BACKGROUND' => metadata[:background_start] ? '1' : nil },
                                 [Blindly::BINARY, Blindly::BINARY], '--test-app',
                                 in: File::NULL, out: File::NULL, err: File::NULL)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    previous_ready = nil
    loop do
      visible = success('apps').fetch('apps').any? { |app| app.fetch('pid') == @fixture_pid }
      if visible
        activation = cli('activate', '--pid', @fixture_pid)
        frontmost = activation.status == 0
        ready = cli('find', '--pid', @fixture_pid, '--title', 'Fixture ready', '--role', 'AXStaticText', '--limit', '1')
        observed = ready.status == 0 ? ready.json : nil
        settled = frontmost && observed && observed.fetch('matches').any? { |row| row.fetch('title') == 'Fixture ready' }
        break if settled && observed == previous_ready
        previous_ready = settled ? observed : nil
      end
      raise 'The fixture exited before opening' if Process.waitpid(@fixture_pid, Process::WNOHANG)
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "The fixture was not ready in the foreground within 10 seconds; activation: #{activation&.stdout}; readiness: #{observed.inspect}"
      end
      sleep 0.1
    end
  end

  def stop_fixture
    return unless @fixture_pid

    Process.kill('KILL', @fixture_pid)
    Process.waitpid(@fixture_pid)
  rescue Errno::ESRCH, Errno::ECHILD
  ensure
    @fixture_pid = nil
  end

  def app(command, *arguments)
    success(command, '--pid', @fixture_pid, *arguments)
  end

  def rejected_app(status, command, *arguments)
    result = cli(command, '--pid', @fixture_pid, *arguments)
    expect(result.status).to eq(status), "#{command}: #{result.stdout}\n#{result.stderr}"
    if status == 64 && Blindly::MACOS
      expect(result.stdout).to eq('')
      expect(result.stderr).to match(/\S/)
      return
    end
    code = status == 64 ? 'usage_error' : 'accessibility_error'
    expect(result.json).to include('code' => code, 'error' => a_string_matching(/\S/))
    result.json
  end

  def find_control(title, role = nil)
    matches = app('find', '--title', title, '--depth', 6, *(role ? ['--role', role] : [])).fetch('matches')
    expect(matches.length).to eq(1), "Expected one #{role} named #{title}, got #{matches.inspect}"
    matches.first
  end

  def find_control_path(title, role)
    find_control(title, role).fetch('path')
  end

  def draft
    find_control_path('Draft', 'AXTextField')
  end

  def submit
    find_control_path('Submit test draft', 'AXButton')
  end

  def draft_value
    field_value('Draft')
  end

  def set_draft(text)
    app('set-value', '--path', draft, '--value', text)
  end

  def expect_not_submitted
    expect(app('find', '--title', 'Not submitted').fetch('matches').length).to eq(1)
  end

  def field_value(title)
    find_control(title, 'AXTextField').fetch('value')
  end

  def visible_label(prefix)
    app('find', '--title', prefix, '--role', 'AXStaticText').fetch('matches')
      .map { |row| row.fetch('title') }.find { |title| title.start_with?(prefix) }
  end

  def wait_for_observed_state(description = 'Expected desktop state')
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      observed = yield
      return if observed
      raise "#{description} was not observed within 5 seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.05
    end
  end

  def expect_label(text)
    wait_for_observed_state("Visible label #{text.inspect}") { visible_label(text) == text }
  end

  def with_clipboard_fixture
    Open3.popen3([Blindly::BINARY, Blindly::BINARY], '--test-pasteboard') do |input, output, error, process|
      begin
        yield lambda { |request|
          input.puts(JSON.generate(request)); input.flush
          JSON.parse(Timeout.timeout(5) { output.gets })
        }
      ensure
        input.close
        begin
          status = Timeout.timeout(5) { process.value.exitstatus }
        rescue Timeout::Error
          Process.kill('KILL', process.pid)
          process.join
          raise
        end
        expect(status).to eq(0), error.read
      end
    end
  end

  def expect_untouched_neighbors
    expect(field_value('First field')).to eq('first untouched')
    expect(field_value('Third field')).to eq('third untouched')
  end
end

RSpec.shared_context 'a native desktop fixture' do
  include DesktopFixture

  around do |example|
    start_fixture_with_live_opt_in
    example.run
    if example.exception
      RSpec.configuration.reporter.message("Fixture focus: #{cli('focused', '--pid', @fixture_pid).stdout.strip}")
      RSpec.configuration.reporter.message("Fixture draft: #{cli('find', '--pid', @fixture_pid, '--title', 'Draft', '--role', 'AXTextField').stdout.strip}")
    end
  ensure
    stop_fixture
  end
end
