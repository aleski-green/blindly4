require 'support/windows_fixture'

RSpec.describe 'Windows selection and scrolling controls', :windows, :live do
  include_context 'a native Windows fixture'

  it 'checks and unchecks a checkbox through accessible presses' do
    expect_label('Checkbox: unchecked')
    app('press', '--path', control('Test checkbox', 'AXCheckBox'))
    expect_label('Checkbox: checked')
    app('press', '--path', control('Test checkbox', 'AXCheckBox'))
    expect_label('Checkbox: unchecked')
    expect_not_submitted
  end

  it 'toggles the focused checkbox with Space without submitting' do
    app('focus', '--path', control('Test checkbox', 'AXCheckBox'))
    app('key', '--key', 'space')
    expect_label('Checkbox: checked')
    app('key', '--key', 'space')
    expect_label('Checkbox: unchecked')
    expect_label('Submission count: 0')
  end

  it 'selects one list option and clears the previous selection' do
    app('press', '--path', control('Option 02', 'AXRow'), '--require-selected')
    expect(app('inspect', '--path', control('Option 02', 'AXRow'))).to include('selected' => true)
    app('press', '--path', control('Option 03', 'AXRow'), '--require-selected')
    expect(app('inspect', '--path', control('Option 03', 'AXRow'))).to include('selected' => true)
    expect(app('inspect', '--path', control('Option 02', 'AXRow'))).to include('selected' => false)
    expect_not_submitted
  end

  it 'opens the dropdown, selects its second option, and closes it with Escape' do
    expect_label('Dropdown: closed; choice: 1')
    app('focus', '--path', control('Delivery choice', 'AXComboBox'))
    app('show-menu', '--path', control('Delivery choice', 'AXComboBox'))
    expect_label('Dropdown: open; choice: 1')
    app('press', '--path', control('Choice two', 'AXRow'), '--require-selected')
    observe_until { visible_label('Dropdown:').end_with?('choice: 2') }
    app('key', '--key', 'escape')
    expect_label('Dropdown: closed; choice: 2')
    expect_not_submitted
  end

  it 'selects a dropdown option with the keyboard without submitting the form' do
    app('focus', '--path', control('Delivery choice', 'AXComboBox'))
    app('show-menu', '--path', control('Delivery choice', 'AXComboBox'))
    expect_label('Dropdown: open; choice: 1')
    app('key', '--key', 'down')
    app('key', '--key', 'enter')
    expect_label('Dropdown: closed; choice: 2')
    expect_label('Submission count: 0')
  end

  it 'scrolls the list down and back up with actual wheel input' do
    list = app('inspect', '--path', control('Scrollable options', 'AXList'))
    app('click', '--x', list.fetch('position').fetch('x') + 50,
        '--y', list.fetch('position').fetch('y') + 30)
    expect_label('First visible option: 01')
    app('scroll', '--direction', 'down', '--amount', '3')
    observe_until { visible_label('First visible option:').split.last.to_i > 1 }
    app('scroll', '--direction', 'up', '--amount', '3')
    expect_label('First visible option: 01')
    expect_not_submitted
  end

  it 'brings an offscreen list option into view, then returns to the first option' do
    list = app('inspect', '--path', control('Scrollable options', 'AXList'))
    top = list.fetch('position').fetch('y')
    bottom = top + list.fetch('size').fetch('height')
    last = app('inspect', '--path', control('Option 80', 'AXRow'))
    expect(last.fetch('size').fetch('height') > 0 && last.fetch('position').fetch('y').between?(top, bottom)).to be(false)
    app('scroll-to', '--path', control('Option 80', 'AXRow'))
    observe_until do
      row = app('inspect', '--path', control('Option 80', 'AXRow'))
      row.fetch('size').fetch('height') > 0 && row.fetch('position').fetch('y').between?(top, bottom - 1)
    end
    app('scroll-to', '--path', control('Option 01', 'AXRow'))
    expect_label('First visible option: 01')
    expect_not_submitted
  end
end
