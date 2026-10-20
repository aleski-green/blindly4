require 'support/windows_fixture'

RSpec.describe 'Windows clipboard restoration', :windows, :live do
  include_context 'a native Windows fixture'

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
          # GlobalAlloc may pad the allocation; compare every native byte
          # after paste, while independently checking the supplied payload.
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
