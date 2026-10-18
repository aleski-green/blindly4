//! Owned Core Foundation values at the Accessibility C API boundary.
use crate::error::{Error, Result};
use core_foundation::{
    array::{CFArray, CFArrayRef},
    base::{CFType, CFTypeRef, TCFType},
    boolean::CFBoolean,
    dictionary::CFDictionary,
    number::CFNumber,
    string::{CFString, CFStringRef},
    url::CFURL,
};
use core_graphics::geometry::{CGPoint, CGRect, CGSize};
use serde_json::{Value, json};
use std::{ffi::c_void, ptr};

#[link(name = "ApplicationServices", kind = "framework")]
unsafe extern "C" {
    fn AXIsProcessTrusted() -> bool;
    fn AXIsProcessTrustedWithOptions(options: CFTypeRef) -> bool;
    fn AXUIElementCreateApplication(pid: i32) -> CFTypeRef;
    fn AXUIElementCreateSystemWide() -> CFTypeRef;
    fn AXUIElementGetTypeID() -> usize;
    fn AXUIElementGetPid(element: CFTypeRef, pid: *mut i32) -> i32;
    fn AXUIElementSetMessagingTimeout(element: CFTypeRef, seconds: f32) -> i32;
    fn AXUIElementCopyAttributeValue(
        element: CFTypeRef,
        name: CFStringRef,
        value: *mut CFTypeRef,
    ) -> i32;
    fn AXUIElementCopyMultipleAttributeValues(
        element: CFTypeRef,
        names: CFArrayRef,
        options: u32,
        values: *mut CFTypeRef,
    ) -> i32;
    fn AXUIElementCopyAttributeNames(element: CFTypeRef, names: *mut CFTypeRef) -> i32;
    fn AXUIElementCopyActionNames(element: CFTypeRef, names: *mut CFTypeRef) -> i32;
    fn AXUIElementIsAttributeSettable(
        element: CFTypeRef,
        name: CFStringRef,
        settable: *mut u8,
    ) -> i32;
    fn AXUIElementSetAttributeValue(element: CFTypeRef, name: CFStringRef, value: CFTypeRef)
    -> i32;
    fn AXUIElementPerformAction(element: CFTypeRef, name: CFStringRef) -> i32;
    fn AXUIElementCopyElementAtPosition(
        element: CFTypeRef,
        x: f32,
        y: f32,
        result: *mut CFTypeRef,
    ) -> i32;
    fn AXValueGetTypeID() -> usize;
    fn AXValueGetValue(value: CFTypeRef, kind: i32, result: *mut c_void) -> bool;
}

pub fn require_accessibility() -> Result<()> {
    if unsafe { AXIsProcessTrusted() } {
        return Ok(());
    }
    Err(Error { message: "Accessibility access is not enabled. Run `blindly4 request-permission`, then enable your terminal or host in System Settings > Privacy & Security > Accessibility.".into(), exit: 77, code: "accessibility_permission_denied" })
}
pub fn request_permission() -> bool {
    let options = CFDictionary::from_CFType_pairs(&[(
        CFString::new("AXTrustedCheckOptionPrompt"),
        CFBoolean::true_value(),
    )]);
    unsafe { AXIsProcessTrustedWithOptions(options.as_CFTypeRef()) }
}

pub fn check(status: i32, operation: &str) -> Result<()> {
    if status == 0 {
        Ok(())
    } else {
        Err(Error::access(format!(
            "{operation} failed (AXError {status}); rediscover the target"
        )))
    }
}

// Copy/Create APIs transfer one owned reference. CFType releases it on every path.
fn owned(value: CFTypeRef) -> Result<CFType> {
    if value.is_null() {
        return Err(Error::access("Accessibility returned a null value"));
    }
    Ok(unsafe { CFType::wrap_under_create_rule(value) })
}
pub fn application(pid: i32) -> Result<CFType> {
    let value = owned(unsafe { AXUIElementCreateApplication(pid) })?;
    check(
        unsafe { AXUIElementSetMessagingTimeout(value.as_CFTypeRef(), 2.0) },
        "Set AX timeout",
    )?;
    Ok(value)
}
pub fn system() -> Result<CFType> {
    owned(unsafe { AXUIElementCreateSystemWide() })
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
    check(
        unsafe { AXUIElementGetPid(value.as_CFTypeRef(), &mut pid) },
        "Read AX process",
    )?;
    Ok(pid)
}
pub fn attribute(element: &CFType, name: &str) -> Result<Option<CFType>> {
    let mut value = ptr::null();
    let name = CFString::new(name);
    let status = unsafe {
        AXUIElementCopyAttributeValue(
            element.as_CFTypeRef(),
            name.as_concrete_TypeRef(),
            &mut value,
        )
    };
    // Unsupported attributes and absent values are normal; IPC failures are not.
    if status == -25205 || status == -25212 {
        return Ok(None);
    }
    check(status, &format!("Read {name}"))?;
    owned(value).map(Some)
}
pub fn array(value: &CFType) -> Result<Vec<CFType>> {
    let array = value
        .downcast::<CFArray>()
        .ok_or_else(|| Error::access("Accessibility returned a non-array"))?;
    Ok(array
        .iter()
        .map(|value| unsafe { CFType::wrap_under_get_rule(*value) })
        .collect())
}
pub fn names(element: &CFType, actions: bool) -> Result<Vec<String>> {
    let mut value = ptr::null();
    let status = unsafe {
        if actions {
            AXUIElementCopyActionNames(element.as_CFTypeRef(), &mut value)
        } else {
            AXUIElementCopyAttributeNames(element.as_CFTypeRef(), &mut value)
        }
    };
    if actions && status == -25206 {
        return Ok(vec![]);
    }
    check(
        status,
        if actions {
            "List AX actions"
        } else {
            "List AX attributes"
        },
    )?;
    let mut names: Vec<_> = array(&owned(value)?)?
        .into_iter()
        .filter_map(|value| value.downcast::<CFString>().map(|s| s.to_string()))
        .collect();
    names.sort();
    Ok(names)
}
pub fn settable(element: &CFType, name: &str) -> Result<bool> {
    let mut value = 0;
    let status = unsafe {
        AXUIElementIsAttributeSettable(
            element.as_CFTypeRef(),
            CFString::new(name).as_concrete_TypeRef(),
            &mut value,
        )
    };
    if status == -25205 {
        return Ok(false);
    }
    check(status, "Read writable attribute")?;
    Ok(value != 0)
}
pub fn set(element: &CFType, name: &str, value: &impl TCFType) -> Result<()> {
    check(
        unsafe {
            AXUIElementSetAttributeValue(
                element.as_CFTypeRef(),
                CFString::new(name).as_concrete_TypeRef(),
                value.as_CFTypeRef(),
            )
        },
        &format!("Set {name}"),
    )
}
pub fn action(element: &CFType, name: &str) -> Result<()> {
    check(
        unsafe {
            AXUIElementPerformAction(
                element.as_CFTypeRef(),
                CFString::new(name).as_concrete_TypeRef(),
            )
        },
        name,
    )
}
pub fn hit_test(x: f64, y: f64) -> Result<CFType> {
    let mut value = ptr::null();
    check(
        unsafe {
            AXUIElementCopyElementAtPosition(
                system()?.as_CFTypeRef(),
                x as f32,
                y as f32,
                &mut value,
            )
        },
        "Hit test",
    )?;
    element(owned(value)?)
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
        let mut point = CGPoint::new(0.0, 0.0);
        let mut size = CGSize::new(0.0, 0.0);
        let mut rect = CGRect::new(&point, &size);
        unsafe {
            if AXValueGetValue(value.as_CFTypeRef(), 1, (&mut point as *mut CGPoint).cast()) {
                return Some(json!({"x": point.x, "y": point.y}));
            }
            if AXValueGetValue(value.as_CFTypeRef(), 2, (&mut size as *mut CGSize).cast()) {
                return Some(json!({"width": size.width, "height": size.height}));
            }
            if AXValueGetValue(value.as_CFTypeRef(), 3, (&mut rect as *mut CGRect).cast()) {
                return Some(
                    json!({"x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height}),
                );
            }
        }
    }
    None
}

// One AX IPC per summary, retaining only scalar/geometry values. Error-valued
// members represent unavailable attributes and are deliberately omitted.
pub fn attributes(
    element: &CFType,
    names: &[&str],
) -> Result<std::collections::BTreeMap<String, Value>> {
    let keys: Vec<_> = names.iter().map(|name| CFString::new(name)).collect();
    let requested = CFArray::from_CFTypes(&keys);
    let mut values = ptr::null();
    let status = unsafe {
        AXUIElementCopyMultipleAttributeValues(
            element.as_CFTypeRef(),
            requested.as_concrete_TypeRef(),
            0,
            &mut values,
        )
    };
    if status == -25205 || status == -25208 {
        let mut result = std::collections::BTreeMap::new();
        for name in names {
            if let Some(value) = attribute(element, name)?.as_ref().and_then(json_value) {
                result.insert((*name).to_owned(), value);
            }
        }
        return Ok(result);
    }
    check(status, "Read AX summary")?;
    let values = array(&owned(values)?)?;
    if values.len() != names.len() {
        return Err(Error::access("AX summary has an unexpected length"));
    }
    Ok(names
        .iter()
        .zip(values)
        .filter_map(|(name, value)| json_value(&value).map(|value| ((*name).to_owned(), value)))
        .collect())
}
