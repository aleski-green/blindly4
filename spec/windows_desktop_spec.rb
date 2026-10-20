require 'support/desktop_fixture'

RSpec.describe 'Windows desktop behavior', :windows, :live do
  include_context 'a native desktop fixture'

  it 'reports matching native control types, roles, and supported actions' do
    [ ['Draft', 'AXTextField', 'Edit', []],
      ['Password', 'AXSecureTextField', 'Edit', []],
      ['Submit test draft', 'AXButton', 'Button', ['AXPress']],
      ['Test checkbox', 'AXCheckBox', 'CheckBox', ['AXPress']],
      ['Delivery choice', 'AXComboBox', 'ComboBox', ['AXShowMenu']],
      ['Scrollable options', 'AXList', 'List', []],
      ['Option 02', 'AXRow', 'ListItem', ['AXPress', 'AXScrollToVisible']],
      ['Fixture ready', 'AXStaticText', 'Text', []] ].each do |title, role, control_type, actions|
      path = find_control_path(title, role)
      row = app('inspect', '--path', path)
      expect(row).to include('role' => role, 'subrole' => "ControlType.#{control_type}")
      expect(row.fetch('actions')).to include(*actions) unless actions.empty?
      expect(app('actions', '--path', path)).to eq('path' => path, 'actions' => row.fetch('actions'))
    end
    expect_not_submitted
    app('press', '--path', submit, '--expect-description', 'Submit', '--require-value-path', draft, '--require-value', '')
    expect_label('Submission count: 1')
  end

  it 'keeps the application root readable while rejecting control mutations' do
    set_draft('unchanged')
    expect(app('actions', '--path', '')).to eq('path' => '', 'actions' => [])
    %w[focus press show-menu scroll-to].each do |command|
      rejected_app(64, command, '--path', '')
    end
    rejected_app(64, 'set-value', '--path', '', '--value', 'never entered')
    rejected_app(64, 'paste', '--target-path', '', '--text', 'never entered')
    rejected_app(64, 'key', '--key', 'enter', '--target-path', '', '--require-value', 'unchanged')
    expect(draft_value).to eq('unchanged')
    expect_not_submitted
  end

  %w[ctrl+a command+a cmd+a].each do |shortcut|
    it "selects the matching draft with #{shortcut} and types Unicode through real keyboard input" do
      set_draft('original')
      app('focus', '--path', draft)
      expect(app('key', '--key', shortcut, '--target-path', draft, '--require-value', 'original')).to include('verified' => true)
      app('type', '--text', 'Typed Unicode: مرحبا café 🪟')
      expect(draft_value).to eq('Typed Unicode: مرحبا café 🪟')
      expect_not_submitted
    end
  end

  it 'preserves backward-delete and forward-delete keyboard behavior' do
    set_draft('abc')
    app('focus', '--path', draft)
    app('key', '--key', 'end')
    app('key', '--key', 'delete')
    expect(draft_value).to eq('ab')
    app('key', '--key', 'home')
    app('key', '--key', 'forward-delete')
    expect(draft_value).to eq('b')
  end

  it 'refuses input addressed to a process without a visible target window' do
    result = cli('key', '--pid', Process.pid, '--key', 'return')
    expect(result.status).to eq(77)
    expect(result.json.fetch('code')).to eq('accessibility_error')
    expect_not_submitted
  end
end
