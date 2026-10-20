require 'support/desktop_fixture'

RSpec.describe 'Windows clipboard restoration', :windows, :live do
  include_context 'a native desktop fixture'

  unicode = "clipboard مرحبا café 🪟\0".encode(Encoding::UTF_16LE).bytes
  {
    'an empty clipboard' => {},
    'Unicode text' => { 'CF_UNICODETEXT' => unicode },
    'Unicode text and multiple binary formats' => {
      'CF_UNICODETEXT' => unicode,
      'org.blindly4.fixture' => [0, 255, 17, 0],
      'org.blindly4.fixture-second' => [1, 2, 3, 128]
    }
  }.each do |description, formats|
    it "preserves #{description} after verified paste" do
      with_clipboard_fixture do |clipboard|
        original = clipboard.call('write' => formats)
        expect(original.fetch('data').keys).to match_array(formats.keys)
        formats.each do |name, bytes|
          observed = original.fetch('data').fetch(name)
          expect(observed.take(bytes.length)).to eq(bytes)
          expect(observed.drop(bytes.length)).to all(eq(0))
        end
        expect(original.fetch('formats')).to be_empty if formats.empty?

        ['', 'pasted into fixture only: مرحبا café 🪟'].each do |text|
          set_draft('replace this draft')
          expect(app('paste', '--target-path', draft, '--text', text)).to include('verified' => true)
          expect(draft_value).to eq(text)
          expect(clipboard.call({})).to eq(original)
          expect_not_submitted
        end
      end
    end
  end

  it 'restores the pre-test clipboard when the transport exits after a paste' do
    with_clipboard_fixture do |outer|
      original = outer.call('write' => { 'org.blindly4.fixture-original' => [0, 128, 255, 17] })
      with_clipboard_fixture do |inner|
        expect(inner.call('write' => {}).fetch('formats')).to be_empty
        app('paste', '--target-path', draft, '--text', 'cleanup check')
        expect(draft_value).to eq('cleanup check')
      end
      expect(outer.call({})).to eq(original)
    end
    expect_not_submitted
  end
end
