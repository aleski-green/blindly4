use crate::{
    error::{Error, Result},
    guards,
    invocation::Invocation,
    native,
    node::Node,
};
use serde_json::{Value, json};
use std::{thread::sleep, time::Duration};

pub struct Desktop {
    pub root: Node,
}
impl Desktop {
    pub fn new(pid: i32) -> Result<Self> {
        if pid <= 0 || !native::windows()?.iter().any(|w| w.pid == pid) {
            return Err(Error::access(format!("No visible windows for PID {pid}")));
        }
        Ok(Self {
            root: Node::root(pid)?,
        })
    }
    pub fn resolve(&self, path: &str) -> Result<Node> {
        let mut node = self.root.clone();
        for index in guards::path(path)? {
            node = node.children()?.into_iter().nth(index).ok_or_else(|| {
                Error::access(format!(
                    "Path {path} no longer exists; rediscover the target"
                ))
            })?;
        }
        Ok(node)
    }
}
pub fn tree(i: &Invocation) -> Result<()> {
    let mut remaining = i.integer("max-nodes", 250, 1, 10000)?;
    let depth = i.integer("depth", 4, 0, 64)?;
    let desktop = Desktop::new(i.pid()?)?;
    let mut truncated = false;
    fn build(n: &Node, depth: i32, remaining: &mut i32, truncated: &mut bool) -> Result<Value> {
        *remaining -= 1;
        let mut row = n.detail(None)?;
        let mut children = vec![];
        for child in n.children()? {
            if *remaining == 0 || depth == 0 {
                *truncated = true;
                break;
            }
            children.push(build(&child, depth - 1, remaining, truncated)?);
        }
        if !children.is_empty() {
            row["children"] = json!(children);
        }
        Ok(row)
    }
    let tree = build(&desktop.root, depth, &mut remaining, &mut truncated)?;
    crate::json(&json!({"tree": tree, "truncated": truncated}))
}
fn walk_bounded_depth_first(
    root: Node,
    depth: i32,
    mut visit: impl FnMut(&Node, &str) -> Result<bool>,
) -> Result<bool> {
    let mut stack = vec![(root, String::new(), depth)];
    let mut count = 0;
    while let Some((node, path, depth)) = stack.pop() {
        if count == 10000 {
            return Ok(true);
        }
        count += 1;
        if !visit(&node, &path)? {
            return Ok(true);
        }
        if depth > 0 {
            for (index, child) in node.children()?.into_iter().enumerate().rev() {
                let next = if path.is_empty() {
                    index.to_string()
                } else {
                    format!("{path}.{index}")
                };
                stack.push((child, next, depth - 1));
            }
        }
    }
    Ok(false)
}
pub fn show(i: &Invocation) -> Result<()> {
    let depth = i.integer("depth", 4, 0, 64)?;
    let truncated = walk_bounded_depth_first(Desktop::new(i.pid()?)?.root, depth, |node, path| {
        let row = node.detail(None)?;
        println!(
            "{path:<18} {} {} {}",
            row["role"].as_str().unwrap_or(""),
            row["title"].as_str().unwrap_or(""),
            row["value"].as_str().unwrap_or("")
        );
        Ok(true)
    })?;
    if truncated {
        println!("[truncated: 10000 nodes]");
    }
    Ok(())
}
pub fn find(i: &Invocation) -> Result<()> {
    let filters: Vec<_> = ["title", "role", "value", "description"]
        .into_iter()
        .filter_map(|k| i.optional(k).map(|v| (k, v.to_lowercase())))
        .collect();
    if filters.is_empty() {
        return Err(Error::usage(
            "find requires --title, --role, --value or --description",
        ));
    }
    let limit = i.integer("limit", 25, 1, 10000)? as usize;
    let depth = i.integer("depth", 8, 0, 64)?;
    let mut matches = vec![];
    let truncated = walk_bounded_depth_first(Desktop::new(i.pid()?)?.root, depth, |node, path| {
        let row = node.detail(Some(path))?;
        if filters
            .iter()
            .all(|(k, v)| row[*k].as_str().unwrap_or("").to_lowercase().contains(v))
        {
            matches.push(row);
        }
        Ok(matches.len() < limit)
    })?;
    crate::json(&json!({"matches": matches, "truncated": truncated}))
}
pub fn focused(i: &Invocation) -> Result<()> {
    let pid = i.pid()?;
    let unavailable = || Error {
        message: "No focused control in the requested application".into(),
        exit: 77,
        code: "focus_unavailable",
    };
    if i.has("pid") && native::foreground_pid() != pid {
        return Err(unavailable());
    }
    let root = Node::root(pid)?;
    let element = unsafe { root.automation.GetFocusedElement() }.map_err(|_| unavailable())?;
    let node = root
        .with_same_process_element(element)
        .map_err(|_| unavailable())?;
    crate::json(&node.detail(None)?)
}
pub fn mutate(
    i: &Invocation,
    action: &str,
    mutate: impl FnOnce(&Node) -> Result<()>,
) -> Result<()> {
    let path = i.value("path")?;
    mutate(&Desktop::new(i.pid()?)?.resolve(path)?)?;
    crate::json(&json!({"path": path, "action": action, "ok": true}))
}
pub fn press(i: &Invocation) -> Result<()> {
    i.pair("require-value-path", "require-value", false)?;
    let desktop = Desktop::new(i.pid()?)?;
    let path = i.value("path")?;
    let target = desktop.resolve(path)?;
    if let Some(expected) = i.optional("expect-description") {
        if !target.detail(None)?["description"]
            .as_str()
            .unwrap_or("")
            .to_lowercase()
            .contains(&expected.to_lowercase())
        {
            return Err(Error::usage(
                "press target does not match --expect-description",
            ));
        }
    }
    if let Some(draft_path) = i.optional("require-value-path") {
        if !desktop
            .resolve(draft_path)?
            .exact_draft(i.value("require-value")?)?
        {
            return Err(Error::access(
                "Press blocked: the draft does not exactly match --require-value",
            ));
        }
    }
    target.press()?;
    if i.has("require-selected") {
        for _ in 0..20 {
            if target.selected()? {
                break;
            }
            sleep(Duration::from_millis(50));
        }
        if !target.selected()? {
            return Err(Error::access(
                "Press completed but target was not selected; do not continue",
            ));
        }
    }
    let mut result = json!({"path": path, "action": "AXPress", "ok": true});
    if i.has("require-selected") {
        result["selected"] = json!(true);
    }
    if i.has("require-value-path") {
        result["verified"] = json!(true);
    }
    crate::json(&result)
}
