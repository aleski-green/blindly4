use crate::{
    error::{Error, Result},
    platform,
};

pub fn require_foreground(pid: i32) -> Result<()> {
    if pid <= 0 || platform::foreground_pid() != pid {
        return Err(Error::access(
            "Target application is not frontmost; refusing cross-app input",
        ));
    }
    Ok(())
}
pub fn activate(pid: i32) -> Result<()> {
    if pid > 0 && platform::foreground_pid() == pid {
        return Ok(());
    }
    platform::activate_native(pid)?;
    for _ in 0..20 {
        platform::wait(0.05);
        if platform::foreground_pid() == pid {
            return Ok(());
        }
    }
    require_foreground(pid)
}
