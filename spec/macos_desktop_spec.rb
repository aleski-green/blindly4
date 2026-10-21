require 'support/form_examples'

RSpec.describe 'A native macOS form', :macos, :live do
  include_context 'a native desktop fixture'
  include_examples 'a three-field form'

  it 'preserves native role matching' do
    expect(app('find', '--role', 'TextField').fetch('matches').map { |row| row['role'] }.uniq).to eq(['AXTextField'])
    expect(app('find', '--role', 'Text').fetch('matches')).to be_empty
  end

  it 'reads an omitted empty value and verifies replacement and submission', value_mode: 'empty' do
    expect(app('inspect', '--path', draft)).to include('value' => '')
    expect(app('paste', '--target-path', draft, '--text', 'verified draft')).to include('verified' => true)
    expect(draft_value).to eq('verified draft')
    app('press', '--path', submit, '--require-value-path', draft, '--require-value', 'verified draft')
    expect_label('Submitted: verified draft')
    expect_label('Submission count: 1')
    expect_untouched_neighbors
  end

  it 'traverses the virtual Touch Bar without treating it as an actionable control' do
    tree = app('tree', '--depth', 12, '--max-nodes', 1000)
    expect(tree.fetch('truncated')).to be(false)
    expect(tree.to_json).to include('AXFunctionRowTopLevelElement')
    row = app('find', '--role', 'AXFunctionRowTopLevelElement', '--depth', 2).fetch('matches').fetch(0)
    path = row.fetch('path')
    expect(app('inspect', '--path', path)).to include('role' => 'AXFunctionRowTopLevelElement', 'actions' => [])
    expect(app('actions', '--path', path).fetch('actions')).to eq([])
    outline = cli('show', '--pid', @fixture_pid, '--depth', 2)
    expect(outline.status).to eq(0)
    expect(outline.stdout).to include('AXFunctionRowTopLevelElement')
    rejected_app(77, 'press', '--path', path)
    expect(app('actions', '--path', submit).fetch('actions')).to include('AXPress')
    expect(draft_value).to eq('')
    expect_untouched_neighbors
    expect_not_submitted
  end

  it 'discovers unavailable action metadata without requiring a special role', discovery_role: 'AXGroup' do
    row = find_control('Unavailable actions', 'AXGroup')
    expect(row.fetch('actions')).to eq([])
    expect(app('tree', '--depth', 6, '--max-nodes', 1000).to_json).to include('Submit test draft')
    rejected_app(77, 'press', '--path', row.fetch('path'))
    expect_not_submitted
  end

  %w[unreadable invalid-count].each do |mode|
    it "does not infer an empty draft in #{mode} mode", value_mode: mode do
      set_draft('unreadable draft')
      expect(app('inspect', '--path', draft)).not_to have_key('value')
      app('focus', '--path', draft)
      rejected_app(77, 'key', '--key', 'enter', '--target-path', draft, '--require-value', 'anything')
      rejected_app(77, 'press', '--path', submit, '--require-value-path', draft, '--require-value', '')
      expect_untouched_neighbors
      expect_not_submitted
    end
  end

  it 'opens and dismisses a native popup menu without submitting' do
    app('show-menu', '--path', find_control_path('Delivery choice', 'AXPopUpButton'))
    expect(app('find', '--role', 'AXMenuItem', '--title', 'Choice two').fetch('matches')).not_to be_empty
    app('key', '--key', 'escape')
    expect_not_submitted
  end

  it 'preserves empty and multi-item binary clipboard contents after verified paste' do
    with_clipboard_fixture do |clipboard|
      [[], [
        { 'public.utf8-plain-text' => 'clipboard café'.bytes, 'org.blindly4.fixture' => [0, 255, 17, 0] },
        { 'org.blindly4.fixture-second' => [1, 2, 3, 128] }
      ]].each do |items|
        original = clipboard.call('write' => items)
        expect(original).to eq(items)
        app('paste', '--target-path', draft, '--text', 'pasted into fixture only')
        expect(draft_value).to eq('pasted into fixture only')
        expect(clipboard.call({})).to eq(original)
      end
    end
    expect_not_submitted
  end

  it 'clicks the target field and scrolls the native scroll view in both directions' do
    field = app('inspect', '--path', draft)
    app('click', '--x', field.fetch('position').fetch('x') + 40, '--y', field.fetch('position').fetch('y') + 12)
    expect(app('focused')).to include('title' => 'Draft')
    scroll = app('inspect', '--path', find_control_path('Scrollable options', 'AXScrollArea'))
    x = scroll.fetch('position').fetch('x') + 100
    y = scroll.fetch('position').fetch('y') + 100
    app('click', '--x', x, '--y', y)
    before = find_control('Option 40', 'AXStaticText').fetch('position').fetch('y')
    app('scroll', '--direction', 'up', '--amount', 10)
    wait_for_observed_state do
      find_control('Option 40', 'AXStaticText').fetch('position').fetch('y') != before
    end
    app('scroll', '--direction', 'down', '--amount', 10)
    wait_for_observed_state do
      (find_control('Option 40', 'AXStaticText').fetch('position').fetch('y') - before).abs < 2
    end
    rejected_app(64, 'scroll-to', '--path', draft)
    expect_not_submitted
  end

  it 'delivers every Unicode event from successive short-lived typing processes' do
    10.times do |index|
      message = "#{index}: " + ('abcdefghij مرحبا café 🪟 ' * 3)
      set_draft('')
      app('focus', '--path', draft)
      result = app('type', '--text', message)
      expect(result.fetch('characters')).to eq(message.scan(/\X/).length)
      expect(draft_value).to eq(message)
    end
    expect_untouched_neighbors
    expect_not_submitted
  end

end
