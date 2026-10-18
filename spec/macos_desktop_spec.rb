require 'support/form_examples'

RSpec.describe 'A native macOS form', :macos, :live do
  include_context 'a native desktop fixture'
  include_examples 'a three-field form'

  it 'lists the application, reads its tree, and preserves native AX roles and path semantics' do
    expect(success('apps').fetch('apps')).to include(a_hash_including('pid' => @fixture_pid, 'bundleId' => an_instance_of(String)))
    tree = app('tree', '--depth', 6, '--max-nodes', 1000)
    expect(tree.fetch('tree')).to include('role' => 'AXApplication')
    expect(tree.to_json).to include('Submit test draft')
    expect(app('inspect', '--path', '')).to include('role' => 'AXApplication')
    outline = cli('show', '--pid', @fixture_pid, '--depth', 6)
    expect(outline.status).to eq(0)
    expect(outline.stdout).to include('AXApplication', 'Draft')
    expect(app('actions', '--path', submit).fetch('actions')).to include('AXPress')
    expect(app('find', '--role', 'TextField').fetch('matches').map { |row| row['role'] }.uniq).to eq(['AXTextField'])
    expect(app('find', '--role', 'Text').fetch('matches')).to be_empty
  end

  it 'bounds traversal and redacts secure text values' do
    expect(app('tree', '--max-nodes', 1)).to include('truncated' => true)
    expect(app('find', '--title', 'Draft', '--depth', 0).fetch('matches')).to be_empty
    expect(app('find', '--role', 'AXTextField', '--limit', 1).fetch('matches').length).to eq(1)
    password = find_control_path('Password', 'AXTextField')
    expect(app('inspect', '--path', password)).to include('subrole' => 'AXSecureTextField')
    expect(app('inspect', '--path', password)['value']).to be_nil
    expect(app('tree', '--depth', 6, '--max-nodes', 1000).to_json).not_to include('fixture secret')
    rejected_app(64, 'paste', '--target-path', password, '--text', 'blocked')
    expect_not_submitted
  end

  ['old draft', ' draft', 'draft ', "draft\n", 'Draft'].each do |actual|
    it "rejects the nonmatching draft #{actual.inspect} without submission or editing" do
      set_draft(actual)
      app('focus', '--path', draft)
      rejected_app(77, 'key', '--key', 'enter', '--target-path', draft, '--require-value', 'draft')
      rejected_app(77, 'press', '--path', submit, '--require-value-path', draft, '--require-value', 'draft')
      expect(draft_value).to eq(actual)
      expect_not_submitted
    end
  end

  [['café', "cafe\u0301"], ["\u200fمرحبا", 'مرحبا']].each do |actual, expected|
    it "accepts canonical Unicode draft matching for #{expected.inspect}" do
      set_draft(actual)
      app('press', '--path', submit, '--require-value-path', draft, '--require-value', expected)
      expect_label("Submitted: #{actual}")
      expect_label('Submission count: 1')
    end
  end

  it 'rejects a stale path, wrong button description, wrong focus, and cross-process click' do
    set_draft('unchanged')
    app('focus', '--path', find_control_path('First field', 'AXTextField'))
    rejected_app(77, 'key', '--key', 'enter', '--target-path', draft, '--require-value', 'unchanged')
    rejected_app(64, 'press', '--path', submit, '--expect-description', 'wrong button')
    rejected_app(77, 'inspect', '--path', '99999')
    rejected_app(77, 'click', '--x', -99999, '--y', -99999)
    expect(draft_value).to eq('unchanged')
    expect_not_submitted
  end

  it 'supports an empty verified paste without inserting or submitting text' do
    set_draft('old draft')
    expect(app('paste', '--target-path', draft, '--text', '')).to include('verified' => true)
    expect(draft_value).to eq('')
    expect_not_submitted
  end

  it 'toggles a native checkbox and reads the observed state' do
    checkbox = find_control_path('Test checkbox', 'AXCheckBox')
    app('press', '--path', checkbox)
    expect_label('Checkbox: checked')
    app('press', '--path', find_control_path('Test checkbox', 'AXCheckBox'))
    expect_label('Checkbox: unchecked')
    expect_not_submitted
  end

  it 'opens and dismisses a native popup menu without submitting' do
    app('show-menu', '--path', find_control_path('Delivery choice', 'AXPopUpButton'))
    expect(app('find', '--role', 'AXMenuItem', '--title', 'Choice two').fetch('matches')).not_to be_empty
    app('key', '--key', 'escape')
    expect_not_submitted
  end

  it 'preserves empty and multi-item binary clipboard contents after verified paste' do
    Open3.popen3([Blindly::BINARY, Blindly::BINARY], '--test-pasteboard') do |input, output, error, process|
      begin
        fixtures = [[], [
          { 'public.utf8-plain-text' => 'clipboard café'.bytes, 'org.blindly4.fixture' => [0, 255, 17, 0] },
          { 'org.blindly4.fixture-second' => [1, 2, 3, 128] }
        ]]
        fixtures.each do |items|
          input.puts(JSON.generate('write' => items)); input.flush
          original = JSON.parse(Timeout.timeout(5) { output.gets })
          expect(original).to eq(items)
          app('paste', '--target-path', draft, '--text', 'pasted into fixture only')
          expect(draft_value).to eq('pasted into fixture only')
          input.puts('{}'); input.flush
          expect(JSON.parse(Timeout.timeout(5) { output.gets })).to eq(original)
        end
      ensure
        input.close
        expect(Timeout.timeout(5) { process.value.exitstatus }).to eq(0), error.read
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
    before = app('inspect', '--path', find_control_path('Option 40', 'AXStaticText')).fetch('position').fetch('y')
    app('scroll', '--direction', 'up', '--amount', 10)
    wait_for_observed_state do
      app('inspect', '--path', find_control_path('Option 40', 'AXStaticText')).fetch('position').fetch('y') != before
    end
    app('scroll', '--direction', 'down', '--amount', 10)
    wait_for_observed_state do
      (app('inspect', '--path', find_control_path('Option 40', 'AXStaticText')).fetch('position').fetch('y') - before).abs < 2
    end
    rejected_app(64, 'scroll-to', '--path', draft)
    expect_not_submitted
  end

end
