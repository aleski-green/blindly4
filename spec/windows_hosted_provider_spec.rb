require 'spec_helper'

# Opt-in integration coverage for a real composition WebView, whose native root
# is not parented to the host HWND. Use an empty, non-submitting search field.
RSpec.describe 'Windows composition WebView', :windows, :live do
  it 'uses the host PID for discovery, focused Unicode paste and exact-draft rejection' do
    names = %w[BLINDLY4_HOSTED_PID BLINDLY4_HOSTED_SEARCH_TITLE BLINDLY4_HOSTED_SEARCH_TEXT]
    skip "Set #{names.join(', ')} for an installed composition WebView app" unless names.all? { |name| ENV[name] }
    host_pid = Integer(ENV.fetch(names[0]))
    title, text = names.drop(1).map { |name| ENV.fetch(name) }
    raise 'Search text must not be empty' if text.empty?
    field = lambda do |value = nil|
      filter = value ? ['--value', value] : ['--title', title]
      rows = success('find', '--pid', host_pid, *filter, '--role', 'AXTextField', '--depth', 40, '--limit', 1).fetch('matches')
      expect(rows.length).to eq(1)
      rows.first
    end
    initial = field.call
    expect(initial.fetch('value')).to eq(''), 'Use an empty search field; do not replace an existing draft'
    expect(initial.fetch('title')).to eq(title)
    expect(initial.fetch('identifier')).not_to eq('')
    expect(initial.fetch('pid')).to eq(host_pid)
    begin
      expect(success('paste', '--pid', host_pid, '--target-path', initial.fetch('path'), '--text', text)).to include('verified' => true)
      expect(success('focused', '--pid', host_pid)).to include('identifier' => initial.fetch('identifier'), 'value' => text, 'pid' => host_pid)
      expect(success('apps').fetch('apps')).to include(a_hash_including('pid' => host_pid, 'frontmost' => true))
      current = field.call(text)
      expect(current.fetch('identifier')).to eq(initial.fetch('identifier'))
      expect(current.fetch('value')).to eq(text)
      rejected = cli('key', '--pid', host_pid, '--key', 'return', '--target-path', current.fetch('path'),
                     '--require-value', "#{text} must not submit")
      expect(rejected.status).to eq(77)
      expect(rejected.json).to include('code' => 'accessibility_error')
      expect(field.call(text).fetch('value')).to eq(text)
    ensure
      focused = cli('focused', '--pid', host_pid)
      current = focused.status == 0 ? focused.json : {}
      if current['identifier'] == initial.fetch('identifier') && current['value'] == text
        current = field.call(text)
        expect(current.fetch('identifier')).to eq(initial.fetch('identifier'))
        success('paste', '--pid', host_pid, '--target-path', current.fetch('path'), '--text', '')
        expect(field.call.fetch('value')).to eq('')
      end
    end
  end
end
