require 'support/form_examples'

RSpec.describe 'A three-field Windows form', :windows, :live do
  include_context 'a native desktop fixture'
  include_examples 'a three-field form'

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

  it 'blocks paste when a successful native clear leaves visible draft text', value_mode: 'retained' do
    rejected_app(77, 'paste', '--target-path', draft, '--text', 'must not be inserted')
    expect(draft_value).to eq('retained draft')
    expect_not_submitted
    expect_untouched_neighbors
  end
end
