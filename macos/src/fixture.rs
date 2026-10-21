use crate::error::{Error, Result};
use objc2::{DefinedClass, MainThreadOnly, define_class, msg_send, rc::Retained, sel};
use objc2_app_kit::{
    NSAccessibility, NSApplication, NSApplicationActivationPolicy, NSBackingStoreType, NSButton, NSEvent, NSEventType, NSMenu, NSMenuItem,
    NSPopUpButton, NSScrollView, NSSecureTextField, NSTextField, NSView, NSWindow, NSWindowStyleMask,
};
use objc2_foundation::{
    MainThreadMarker, NSArray, NSObject, NSObjectNSDelayedPerforming, NSObjectProtocol, NSPoint, NSRect, NSSize, NSString,
};
use std::cell::Cell;

thread_local! { static FOCUS_PENDING: Cell<u8> = const { Cell::new(0) }; }

define_class!(
    #[unsafe(super = NSWindow)]
    #[thread_kind = MainThreadOnly]
    struct FixtureWindow;
    unsafe impl NSObjectProtocol for FixtureWindow {}
    impl FixtureWindow {
        #[unsafe(method(sendEvent:))]
        fn send_event(&self, event: &NSEvent) {
            if event.r#type() == NSEventType::LeftMouseDown && FOCUS_PENDING.with(|pending| pending.get() == 1) {
                FOCUS_PENDING.with(|pending| pending.set(2));
                self.focus_field("First field");
                unsafe { self.performSelector_withObject_afterDelay(sel!(finishFocus:), None, 0.15); }
            } else if event.r#type() == NSEventType::LeftMouseUp && FOCUS_PENDING.with(|pending| pending.get() == 2) {
                // The delayed native click handler has not focused the editor yet.
            } else {
                unsafe { let _: () = msg_send![super(self), sendEvent: event]; }
            }
        }
        #[unsafe(method(finishFocus:))]
        fn finish_focus(&self, _sender: Option<&NSObject>) {
            FOCUS_PENDING.with(|pending| pending.set(0));
            self.focus_field("Draft");
        }
    }
);
impl FixtureWindow {
    fn focus_field(&self, title: &str) {
        if let Some(view) = self.contentView() {
            for field in view.subviews() {
                if field.accessibilityTitle().is_some_and(|value| value.to_string() == title) {
                    self.makeFirstResponder(Some(&field));
                }
            }
        }
    }
}

define_class!(
    #[unsafe(super = NSTextField)]
    #[thread_kind = MainThreadOnly]
    struct OptionalValueField;
    unsafe impl NSObjectProtocol for OptionalValueField {}
    impl OptionalValueField {
        #[unsafe(method(accessibilityValue))]
        fn ax_value(&self) -> *mut NSString {
            let value = self.stringValue();
            match std::env::var("BLINDLY4_FIXTURE_VALUE").as_deref() {
                Ok("empty") if value.is_empty() => std::ptr::null_mut(),
                Ok("unreadable" | "invalid-count") => std::ptr::null_mut(),
                Ok("whitespace") if value.is_empty() => Retained::autorelease_ptr(NSString::from_str("\r\n")),
                _ => Retained::autorelease_ptr(value),
            }
        }
        #[unsafe(method(accessibilityNumberOfCharacters))]
        fn character_count(&self) -> isize {
            if std::env::var("BLINDLY4_FIXTURE_VALUE").as_deref() == Ok("invalid-count") { -1 } else { self.stringValue().length() as isize }
        }
    }
);

define_class!(
    #[unsafe(super = NSView)]
    #[thread_kind = MainThreadOnly]
    struct FunctionRow;
    unsafe impl NSObjectProtocol for FunctionRow {}
    impl FunctionRow {
        #[unsafe(method(accessibilityActionNames))]
        fn action_names(&self) -> *mut NSArray<NSString> {
            std::ptr::null_mut()
        }
    }
);

struct State {
    first: Retained<NSTextField>,
    draft: Retained<NSTextField>,
    submitted: Retained<NSTextField>,
    count_label: Retained<NSTextField>,
    checkbox_label: Retained<NSTextField>,
    dropdown_label: Retained<NSTextField>,
    count: Cell<u32>,
}
define_class!(
    #[unsafe(super = NSObject)]
    #[thread_kind = MainThreadOnly]
    #[ivars = State]
    struct Controller;
    unsafe impl NSObjectProtocol for Controller {}
    impl Controller {
        #[unsafe(method(delayFocus:))]
        fn delay_focus(&self, _sender: &NSObject) {
            if let Some(window) = self.ivars().first.window() { window.makeFirstResponder(Some(&self.ivars().first)); }
            FOCUS_PENDING.with(|pending| pending.set(1));
        }
        #[unsafe(method(submit:))]
        fn submit(&self, _sender: &NSObject) {
            let state = self.ivars();
            state.count.set(state.count.get() + 1);
            update_label(&state.submitted, &format!("Submitted: {}", state.draft.stringValue()));
            update_label(&state.count_label, &format!("Submission count: {}", state.count.get()));
        }
        #[unsafe(method(toggle:))]
        fn toggle(&self, sender: &NSButton) {
            update_label(&self.ivars().checkbox_label, if sender.state() == 0 { "Checkbox: unchecked" } else { "Checkbox: checked" });
        }
        #[unsafe(method(selectChoice:))]
        fn select_choice(&self, sender: &NSPopUpButton) {
            update_label(&self.ivars().dropdown_label, &format!("Choice: {}", sender.indexOfSelectedItem() + 1));
        }
    }
);
fn rect(x: f64, y: f64, w: f64, h: f64) -> NSRect {
    NSRect::new(NSPoint::new(x, y), NSSize::new(w, h))
}
fn update_label(label: &NSTextField, text: &str) {
    let value = NSString::from_str(text);
    label.setStringValue(&value);
    label.setAccessibilityTitle(Some(&value));
}
fn label(view: &NSView, text: &str, y: f64, mtm: MainThreadMarker) -> Retained<NSTextField> {
    let field = NSTextField::labelWithString(&NSString::from_str(text), mtm);
    field.setFrame(rect(20.0, y, 600.0, 24.0));
    update_label(&field, text);
    view.addSubview(&field);
    field
}
fn text_field(view: &NSView, title: &str, value: &str, y: f64, mtm: MainThreadMarker) -> Retained<NSTextField> {
    let field: Retained<NSTextField> = if title == "Draft" && std::env::var_os("BLINDLY4_FIXTURE_VALUE").is_some() {
        let field: Retained<OptionalValueField> =
            unsafe { msg_send![OptionalValueField::alloc(mtm), initWithFrame: rect(20.0, y, 580.0, 28.0)] };
        field.into_super()
    } else {
        NSTextField::initWithFrame(NSTextField::alloc(mtm), rect(20.0, y, 580.0, 28.0))
    };
    field.setStringValue(&NSString::from_str(value));
    field.setAccessibilityTitle(Some(&NSString::from_str(title)));
    field.setAccessibilityIdentifier(Some(&NSString::from_str(title)));
    view.addSubview(&field);
    field
}
fn menu(app: &NSApplication, mtm: MainThreadMarker) {
    let main = NSMenu::new(mtm);
    let edit = NSMenu::new(mtm);
    let item = NSMenuItem::new(mtm);
    item.setTitle(&NSString::from_str("Edit"));
    item.setSubmenu(Some(&edit));
    main.addItem(&item);
    unsafe {
        edit.addItemWithTitle_action_keyEquivalent(&NSString::from_str("Copy"), Some(sel!(copy:)), &NSString::from_str("c"));
        edit.addItemWithTitle_action_keyEquivalent(&NSString::from_str("Paste"), Some(sel!(paste:)), &NSString::from_str("v"));
        edit.addItemWithTitle_action_keyEquivalent(&NSString::from_str("Select All"), Some(sel!(selectAll:)), &NSString::from_str("a"));
    }
    app.setMainMenu(Some(&main));
}
pub fn run() -> Result<()> {
    let mtm = MainThreadMarker::new().ok_or_else(|| Error::unexpected("Fixture must run on the main thread"))?;
    let app = NSApplication::sharedApplication(mtm);
    app.setActivationPolicy(NSApplicationActivationPolicy::Regular);
    menu(&app, mtm);
    let window: Retained<FixtureWindow> = unsafe {
        msg_send![FixtureWindow::alloc(mtm), initWithContentRect: rect(100.0, 100.0, 640.0, 720.0),
                  styleMask: NSWindowStyleMask::Titled | NSWindowStyleMask::Closable,
                  backing: NSBackingStoreType::Buffered, defer: false]
    };
    unsafe {
        window.setReleasedWhenClosed(false);
    }
    window.setTitle(&NSString::from_str("Blindly4 macOS test fixture"));
    let view = window.contentView().ok_or_else(|| Error::unexpected("Fixture has no content view"))?;
    let function_row: Retained<FunctionRow> = unsafe { msg_send![FunctionRow::alloc(mtm), initWithFrame: rect(0.0, 0.0, 20.0, 20.0)] };
    function_row.setAccessibilityElement(true);
    let role = std::env::var("BLINDLY4_FIXTURE_ROLE").unwrap_or_else(|_| "AXFunctionRowTopLevelElement".into());
    function_row.setAccessibilityRole(Some(&NSString::from_str(&role)));
    function_row.setAccessibilityTitle(Some(&NSString::from_str("Unavailable actions")));
    view.addSubview(&function_row);
    label(&view, "Fixture ready", 680.0, mtm);
    let first = text_field(&view, "First field", "first untouched", 640.0, mtm);
    let draft = text_field(&view, "Draft", "", 600.0, mtm);
    text_field(&view, "Third field", "third untouched", 560.0, mtm);
    let password = NSSecureTextField::initWithFrame(NSSecureTextField::alloc(mtm), rect(20.0, 520.0, 580.0, 28.0));
    password.setStringValue(&NSString::from_str("fixture secret"));
    password.setAccessibilityTitle(Some(&NSString::from_str("Password")));
    view.addSubview(&password);
    let state = State {
        first,
        draft: draft.clone(),
        submitted: label(&view, "Not submitted", 440.0, mtm),
        count_label: label(&view, "Submission count: 0", 410.0, mtm),
        checkbox_label: label(&view, "Checkbox: unchecked", 340.0, mtm),
        dropdown_label: label(&view, "Choice: 1", 270.0, mtm),
        count: Cell::new(0),
    };
    let controller: Retained<Controller> = unsafe { msg_send![super(Controller::alloc(mtm).set_ivars(state)), init] };
    unsafe {
        if std::env::var("BLINDLY4_FIXTURE_VALUE").as_deref() == Ok("delayed-focus") {
            let delay = NSButton::buttonWithTitle_target_action(
                &NSString::from_str("Delay draft focus"),
                Some(&controller),
                Some(sel!(delayFocus:)),
                mtm,
            );
            delay.setFrame(rect(300.0, 475.0, 240.0, 32.0));
            view.addSubview(&delay);
        }
        let submit =
            NSButton::buttonWithTitle_target_action(&NSString::from_str("Submit test draft"), Some(&controller), Some(sel!(submit:)), mtm);
        submit.setFrame(rect(20.0, 475.0, 240.0, 32.0));
        submit.setKeyEquivalent(&NSString::from_str("\r"));
        view.addSubview(&submit);
        draft.setTarget(Some(&controller));
        draft.setAction(Some(sel!(submit:)));
        let checkbox =
            NSButton::checkboxWithTitle_target_action(&NSString::from_str("Test checkbox"), Some(&controller), Some(sel!(toggle:)), mtm);
        checkbox.setFrame(rect(20.0, 375.0, 260.0, 28.0));
        view.addSubview(&checkbox);
        let popup = NSPopUpButton::initWithFrame_pullsDown(NSPopUpButton::alloc(mtm), rect(20.0, 300.0, 260.0, 28.0), false);
        for title in ["Choice one", "Choice two", "Choice three"] {
            popup.addItemWithTitle(&NSString::from_str(title));
        }
        popup.setAccessibilityTitle(Some(&NSString::from_str("Delivery choice")));
        popup.setTarget(Some(&controller));
        popup.setAction(Some(sel!(selectChoice:)));
        view.addSubview(&popup);
    }
    let scroll = NSScrollView::initWithFrame(NSScrollView::alloc(mtm), rect(20.0, 30.0, 580.0, 220.0));
    scroll.setHasVerticalScroller(true);
    scroll.setAccessibilityTitle(Some(&NSString::from_str("Scrollable options")));
    let document = NSView::initWithFrame(NSView::alloc(mtm), rect(0.0, 0.0, 540.0, 2400.0));
    for index in 0..80 {
        label(&document, &format!("Option {:02}", index + 1), 2370.0 - index as f64 * 30.0, mtm);
    }
    scroll.setDocumentView(Some(&document));
    view.addSubview(&scroll);
    app.finishLaunching();
    window.makeKeyAndOrderFront(None);
    #[allow(deprecated)]
    app.activateIgnoringOtherApps(true);
    crate::json(&serde_json::json!({"ready": true, "pid": std::process::id()}))?;
    app.run();
    Ok(())
}
