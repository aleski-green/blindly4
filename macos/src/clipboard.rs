use crate::error::{Error, Result};
use objc2::{rc::Retained, runtime::ProtocolObject};
use objc2_app_kit::{NSPasteboard, NSPasteboardItem, NSPasteboardWriting};
use objc2_foundation::{NSArray, NSString};

pub struct Clipboard {
    board: Retained<NSPasteboard>,
    saved: Vec<Retained<NSPasteboardItem>>,
    owned_change: Option<isize>,
    captured_change: isize,
}
impl Clipboard {
    pub fn capture() -> Result<Self> {
        let board = NSPasteboard::generalPasteboard();
        let count = board.changeCount();
        let mut saved = vec![];
        if let Some(items) = board.pasteboardItems() {
            for item in items.iter() {
                let copy = NSPasteboardItem::new();
                for kind in item.types().iter() {
                    let data =
                        item.dataForType(&kind).ok_or_else(|| Error::access("Clipboard format could not be preserved; paste cancelled"))?;
                    if !copy.setData_forType(&data, &kind) {
                        return Err(Error::access("Could not preserve clipboard data"));
                    }
                }
                saved.push(copy);
            }
        }
        if board.changeCount() != count {
            return Err(Error::access("Clipboard changed while being captured; paste cancelled"));
        }
        Ok(Self { board, saved, owned_change: None, captured_change: count })
    }
    pub fn replace(&mut self, text: &str) -> Result<()> {
        if self.board.changeCount() != self.captured_change {
            return Err(Error::access("Clipboard changed before paste; newer contents were left intact"));
        }
        self.owned_change = Some(self.board.clearContents());
        let ok = self.board.setString_forType(&NSString::from_str(text), &NSString::from_str("public.utf8-plain-text"));
        self.owned_change = Some(self.board.changeCount());
        if ok { Ok(()) } else { Err(Error::access("Could not place text on pasteboard")) }
    }
    pub fn restore(&mut self) -> Result<()> {
        let Some(count) = self.owned_change.take() else {
            return Ok(());
        };
        if self.board.changeCount() != count {
            return Err(Error::access("Clipboard changed during paste; newer contents were left intact"));
        }
        self.board.clearContents();
        if self.saved.is_empty() {
            return Ok(());
        }
        let items: Vec<&ProtocolObject<dyn NSPasteboardWriting>> =
            self.saved.iter().map(|item| ProtocolObject::from_ref(&**item)).collect();
        if self.board.writeObjects(&NSArray::from_slice(&items)) {
            Ok(())
        } else {
            Err(Error::access("Could not restore clipboard contents"))
        }
    }
}
impl Drop for Clipboard {
    fn drop(&mut self) {
        let _ = self.restore();
    }
}

// Opt-in fixture transport: RSpec supplies/observes bytes and owns assertions.
// Original user clipboard data never goes to stdout and is restored on EOF when
// the clipboard still contains the fixture's last supplied data.
pub fn fixture() -> Result<()> {
    use objc2_foundation::NSData;
    use serde_json::{Value, json};
    use std::io::BufRead;
    let mut original = Clipboard::capture()?;
    let snapshot = || -> Value {
        let mut result = vec![];
        if let Some(items) = NSPasteboard::generalPasteboard().pasteboardItems() {
            for item in items.iter() {
                let mut row = serde_json::Map::new();
                for kind in item.types().iter() {
                    if let Some(data) = item.dataForType(&kind) {
                        row.insert(kind.to_string(), json!(data.to_vec()));
                    }
                }
                result.push(Value::Object(row));
            }
        }
        json!(result)
    };
    let mut fixture_contents = None;
    for line in std::io::stdin().lock().lines() {
        let request: Value = serde_json::from_str(&line?)?;
        if let Some(rows) = request.get("write").and_then(Value::as_array) {
            let mut items = vec![];
            for row in rows {
                let item = NSPasteboardItem::new();
                for (kind, bytes) in row.as_object().ok_or_else(|| Error::usage("Expected clipboard item"))? {
                    let bytes: Vec<u8> = serde_json::from_value(bytes.clone())?;
                    if !item.setData_forType(&NSData::with_bytes(&bytes), &NSString::from_str(kind)) {
                        return Err(Error::access("Fixture clipboard write failed"));
                    }
                }
                items.push(item);
            }
            original.board.clearContents();
            let objects: Vec<&ProtocolObject<dyn NSPasteboardWriting>> =
                items.iter().map(|item| ProtocolObject::from_ref(&**item)).collect();
            if !objects.is_empty() && !original.board.writeObjects(&NSArray::from_slice(&objects)) {
                return Err(Error::access("Fixture clipboard write failed"));
            }
            original.owned_change = Some(original.board.changeCount());
            fixture_contents = Some(snapshot());
        }
        // Reading is allowed only after RSpec has supplied harmless fixture data.
        if fixture_contents.is_none() {
            return Err(Error::usage("Write fixture data before inspecting it"));
        }
        crate::json(&snapshot())?;
    }
    if fixture_contents.as_ref() == Some(&snapshot()) {
        original.owned_change = Some(original.board.changeCount());
    }
    original.restore()
}
