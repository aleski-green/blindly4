//! Ownership and error handling at the native Accessibility boundary.
use crate::error::{Error, Result};
use accessibility_sys::*;
use core_foundation::{
    array::CFArray,
    base::{CFType, CFTypeRef, TCFType},
    boolean::CFBoolean,
    dictionary::CFDictionary,
    number::CFNumber,
    string::CFString,
    url::CFURL,
};
use core_graphics::geometry::{CGPoint, CGRect, CGSize};
use serde_json::{Value, json};
use std::{ffi::c_void, ptr};

pub fn require_accessibility() -> Result<()> {
    if unsafe { AXIsProcessTrusted() } {
        return Ok(());
    }
    Err(Error { message: "Accessibility access is not enabled. Run `blindly4 request-permission`, then enable your terminal or host in System Settings > Privacy & Security > Accessibility.".into(), exit: 77, code: "accessibility_permission_denied" })
}
pub fn request_permission() -> bool {
    let options = CFDictionary::from_CFType_pairs(&[(CFString::new("AXTrustedCheckOptionPrompt"), CFBoolean::true_value())]);
    unsafe { AXIsProcessTrustedWithOptions(options.as_concrete_TypeRef()) }
}
pub fn check(status: AXError, operation: &str) -> Result<()> {
    if status == kAXErrorSuccess {
        Ok(())
    } else {
        Err(Error::access(format!("{operation} failed (AXError {status}); rediscover the target")))
    }
}
fn raw(value: &CFType) -> AXUIElementRef {
    value.as_CFTypeRef().cast_mut().cast()
}
// Copy/Create APIs transfer one reference; CFType releases it on every path.
fn owned(value: CFTypeRef) -> Result<CFType> {
    if value.is_null() {
        return Err(Error::access("Accessibility returned a null value"));
    }
    Ok(unsafe { CFType::wrap_under_create_rule(value) })
}
fn copied(operation: &str, absent: &[AXError], copy: impl FnOnce(*mut CFTypeRef) -> AXError) -> Result<Option<CFType>> {
    let mut value = ptr::null();
    let status = copy(&mut value);
    if absent.contains(&status) {
        return Ok(None);
    }
    check(status, operation)?;
    owned(value).map(Some)
}
pub fn application(pid: i32) -> Result<CFType> {
    let value = owned(unsafe { AXUIElementCreateApplication(pid) }.cast())?;
    check(unsafe { AXUIElementSetMessagingTimeout(raw(&value), 2.0) }, "Set AX timeout")?;
    Ok(value)
}
pub fn element(value: CFType) -> Result<CFType> {
    if value.type_of() == unsafe { AXUIElementGetTypeID() } {
        Ok(value)
    } else {
        Err(Error::access("Accessibility returned a non-element"))
    }
}
pub fn pid(value: &CFType) -> Result<i32> {
    let mut pid = 0;
    check(unsafe { AXUIElementGetPid(raw(value), &mut pid) }, "Read AX process")?;
    Ok(pid)
}
pub fn attribute(element: &CFType, name: &str) -> Result<Option<CFType>> {
    // Missing attributes are normal; IPC failures must propagate.
    copied(&format!("Read {name}"), &[kAXErrorAttributeUnsupported, kAXErrorNoValue], |out| unsafe {
        AXUIElementCopyAttributeValue(raw(element), CFString::new(name).as_concrete_TypeRef(), out)
    })
}
pub fn array(value: &CFType) -> Result<Vec<CFType>> {
    let array = value.downcast::<CFArray>().ok_or_else(|| Error::access("Accessibility returned a non-array"))?;
    Ok(array.iter().map(|value| unsafe { CFType::wrap_under_get_rule(*value) }).collect())
}
pub fn names(element: &CFType, actions: bool) -> Result<Vec<String>> {
    let (copy, operation, absent): (unsafe extern "C" fn(_, _) -> _, _, &[AXError]) = if actions {
        (AXUIElementCopyActionNames, "List AX actions", &[kAXErrorActionUnsupported])
    } else {
        (AXUIElementCopyAttributeNames, "List AX attributes", &[])
    };
    let mut value = ptr::null();
    let status = unsafe { copy(raw(element), &mut value) };
    // AppKit's virtual Touch Bar container returns failure instead of an empty action list.
    // Only normalize this role/error pair; permission, stale-element and IPC failures stay errors.
    let empty_touch_bar = actions
        && status == kAXErrorFailure
        && attribute(element, "AXRole")?.as_ref().and_then(json_value).as_ref().and_then(Value::as_str)
            == Some("AXFunctionRowTopLevelElement");
    if absent.contains(&status) || empty_touch_bar {
        return Ok(vec![]);
    }
    check(status, operation)?;
    let value = owned(value.cast())?;
    let mut names: Vec<_> = array(&value)?.iter().filter_map(|v| v.downcast::<CFString>().map(|s| s.to_string())).collect();
    names.sort();
    Ok(names)
}
pub fn settable(element: &CFType, name: &str) -> Result<bool> {
    let mut value = 0;
    let status = unsafe { AXUIElementIsAttributeSettable(raw(element), CFString::new(name).as_concrete_TypeRef(), &mut value) };
    if status == kAXErrorAttributeUnsupported {
        return Ok(false);
    }
    check(status, "Read writable attribute")?;
    Ok(value != 0)
}
pub fn set(element: &CFType, name: &str, value: &impl TCFType) -> Result<()> {
    check(
        unsafe { AXUIElementSetAttributeValue(raw(element), CFString::new(name).as_concrete_TypeRef(), value.as_CFTypeRef()) },
        &format!("Set {name}"),
    )
}
pub fn action(element: &CFType, name: &str) -> Result<()> {
    check(unsafe { AXUIElementPerformAction(raw(element), CFString::new(name).as_concrete_TypeRef()) }, name)
}
pub fn hit_test(x: f64, y: f64) -> Result<CFType> {
    let system = owned(unsafe { AXUIElementCreateSystemWide() }.cast())?;
    let value = copied("Hit test", &[], |out| unsafe { AXUIElementCopyElementAtPosition(raw(&system), x as f32, y as f32, out.cast()) })?;
    element(value.unwrap())
}
pub fn json_value(value: &CFType) -> Option<Value> {
    if let Some(s) = value.downcast::<CFString>() {
        return Some(json!(s.to_string()));
    }
    if let Some(b) = value.downcast::<CFBoolean>() {
        return Some(json!(bool::from(b)));
    }
    if let Some(n) = value.downcast::<CFNumber>() {
        return n.to_f64().map(|n| json!(n));
    }
    if let Some(url) = value.downcast::<CFURL>() {
        return Some(json!(url.get_string().to_string()));
    }
    if value.type_of() == unsafe { AXValueGetTypeID() } {
        let value = value.as_CFTypeRef().cast_mut().cast();
        let mut point = CGPoint::new(0.0, 0.0);
        let mut size = CGSize::new(0.0, 0.0);
        let mut rect = CGRect::new(&point, &size);
        unsafe {
            if AXValueGetValue(value, kAXValueTypeCGPoint, (&mut point as *mut CGPoint).cast::<c_void>()) {
                return Some(json!({"x": point.x, "y": point.y}));
            }
            if AXValueGetValue(value, kAXValueTypeCGSize, (&mut size as *mut CGSize).cast::<c_void>()) {
                return Some(json!({"width": size.width, "height": size.height}));
            }
            if AXValueGetValue(value, kAXValueTypeCGRect, (&mut rect as *mut CGRect).cast::<c_void>()) {
                return Some(json!({"x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height}));
            }
        }
    }
    None
}
// One AX IPC per summary. Unsupported batching falls back to individual reads;
// errors inside a successful batch are omitted, as before.
pub fn attributes(element: &CFType, names: &[&str]) -> Result<std::collections::BTreeMap<String, Value>> {
    let keys: Vec<_> = names.iter().map(|name| CFString::new(name)).collect();
    let requested = CFArray::from_CFTypes(&keys);
    let batch = copied("Read AX summary", &[kAXErrorAttributeUnsupported, kAXErrorNotImplemented], |out| unsafe {
        AXUIElementCopyMultipleAttributeValues(raw(element), requested.as_concrete_TypeRef(), 0, out.cast())
    })?;
    let values = match batch {
        Some(batch) => array(&batch)?.iter().map(json_value).collect::<Vec<_>>(),
        None => names.iter().map(|name| Ok(attribute(element, name)?.as_ref().and_then(json_value))).collect::<Result<Vec<_>>>()?,
    };
    if values.len() != names.len() {
        return Err(Error::access("AX summary has an unexpected length"));
    }
    Ok(names.iter().zip(values).filter_map(|(name, value)| value.map(|v| ((*name).to_owned(), v))).collect())
}
