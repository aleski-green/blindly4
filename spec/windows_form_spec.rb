require 'support/form_examples'

RSpec.describe 'A three-field Windows form', :windows, :live do
  include_context 'a native desktop fixture'
  include_examples 'a three-field form'

  it 'waits for an asynchronous focus request without repeating input', value_mode: 'delayed-focus' do
    app('press', '--path', find_control_path('Delay draft focus', 'AXButton'))
    expect(app('focused')).to include('title' => 'First field')
    expect(app('paste', '--target-path', draft, '--text', 'entered once')).to include('verified' => true)
    expect(app('focused')).to include('title' => 'Draft', 'value' => 'entered once')
    expect_not_submitted
    expect_untouched_neighbors
  end

  it 'accepts formatting whitespace after clear without relaxing nonempty draft matching', value_mode: 'whitespace' do
    app('set-value', '--path', draft, '--value', '')
    expect(draft_value).to eq("\r\n")
    expect(app('paste', '--target-path', draft, '--text', 'exact message')).to include('verified' => true)
    expect(draft_value).to eq('exact message')
    set_draft("exact message\r\n")
    rejected_app(77, 'press', '--path', submit, '--require-value-path', draft, '--require-value', 'exact message')
    expect(app('paste', '--target-path', draft, '--text', '')).to include('verified' => true)
    expect(draft_value).to eq("\r\n")
    expect_not_submitted
    expect_untouched_neighbors
  end

  it 'blocks paste when a successful native clear leaves visible draft text', value_mode: 'retained' do
    rejected_app(77, 'paste', '--target-path', draft, '--text', 'must not be inserted')
    expect(draft_value).to eq('retained draft')
    expect_not_submitted
    expect_untouched_neighbors
  end

  it 'verifies the same native draft when another control changes its path during paste', paste_mode: 'reorder' do
    original_path = draft
    expect(app('paste', '--target-path', original_path, '--text', 'same native draft')).to include('verified' => true)
    expect(draft).not_to eq(original_path)
    expect(draft_value).to eq('same native draft')
    expect_not_submitted
    expect(field_value('First field')).to eq('first untouched')
    # Reordering changes the native label association too; use the control ID.
    expect(app('find', '--role', 'AXTextField').fetch('matches'))
      .to include(a_hash_including('identifier' => '110', 'value' => 'third untouched'))
  end
end
