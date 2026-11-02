use std::{collections::HashMap, process::ExitCode};
use zbus::{
    blocking::{Connection, Proxy},
    fdo,
    zvariant::{OwnedObjectPath, OwnedValue, Value},
};

const DESKTOP: &str = "org.freedesktop.portal.Desktop";
const PORTAL: &str = "/org/freedesktop/portal/desktop";
const REMOTE: &str = "org.freedesktop.portal.RemoteDesktop";
type Options<'a> = HashMap<&'a str, Value<'a>>;
type Response = HashMap<String, OwnedValue>;

fn denied(message: impl ToString) -> fdo::Error {
    fdo::Error::AccessDenied(message.to_string())
}

struct Input {
    connection: Connection,
    session: OwnedObjectPath,
    pointer: bool,
}

impl Input {
    fn request(connection: &Connection, method: &str, session: Option<&OwnedObjectPath>, devices: u32) -> zbus::Result<Response> {
        let token = format!("blindly_{method}");
        let sender = connection.unique_name().unwrap().as_str().trim_start_matches(':').replace('.', "_");
        let path = format!("/org/freedesktop/portal/desktop/request/{sender}/{token}");
        let request = Proxy::new(connection, DESKTOP, path.as_str(), "org.freedesktop.portal.Request")?;
        let mut responses = request.receive_signal("Response")?;
        let portal = Proxy::new(connection, DESKTOP, PORTAL, REMOTE)?;
        let mut options = Options::from([("handle_token", Value::from(token.as_str()))]);
        let returned: OwnedObjectPath = match method {
            "CreateSession" => {
                options.insert("session_handle_token", Value::from("blindly_input"));
                portal.call(method, &options)?
            }
            "SelectDevices" => {
                options.insert("types", Value::from(devices));
                options.insert("persist_mode", Value::from(0u32));
                portal.call(method, &(session.unwrap(), options))?
            }
            _ => portal.call(method, &(session.unwrap(), "", options))?,
        };
        if returned.as_str() != path {
            return Err(denied("Portal returned an unexpected request path").into());
        }
        let message = responses.next().ok_or_else(|| denied("Portal disconnected"))?;
        let (code, values): (u32, Response) = message.body().deserialize()?;
        if code != 0 {
            return Err(denied("Input consent was cancelled or declined").into());
        }
        Ok(values)
    }
    fn consent(connection: Connection, pointer: bool) -> zbus::Result<Self> {
        let requested = if pointer { 3 } else { 1 };
        let mut created = Self::request(&connection, "CreateSession", None, requested)?;
        let path = String::try_from(created.remove("session_handle").ok_or_else(|| denied("Missing portal session"))?)?;
        let session = OwnedObjectPath::try_from(path)?;
        Self::request(&connection, "SelectDevices", Some(&session), requested)?;
        let mut started = Self::request(&connection, "Start", Some(&session), requested)?;
        let devices = u32::try_from(started.remove("devices").ok_or_else(|| denied("Missing granted devices"))?)?;
        if devices & requested != requested {
            return Err(denied("Requested input access was not granted").into());
        }
        if pointer {
            let portal = Proxy::new(&connection, DESKTOP, PORTAL, REMOTE)?;
            portal.call::<_, _, ()>("NotifyPointerMotion", &(&session, Options::new(), 0.0f64, 0.0f64))?;
        }
        Ok(Self { connection, session, pointer })
    }
    async fn foreground(&self, pid: u32) -> fdo::Result<()> {
        let proxy = zbus::Proxy::new(
            self.connection.inner(),
            "org.gnome.Shell",
            "/org/sapiens/Blindly/Foreground",
            "org.sapiens.Blindly.Foreground1",
        )
        .await
        .map_err(denied)?;
        let foreground: u32 = proxy.call("Get", &()).await.map_err(denied)?;
        if pid == 0 || foreground != pid {
            return Err(denied("Foreground PID could not be verified"));
        }
        Ok(())
    }
    async fn event(&self, key: i32, pressed: bool) -> fdo::Result<()> {
        zbus::Proxy::new(self.connection.inner(), DESKTOP, PORTAL, REMOTE)
            .await
            .map_err(denied)?
            .call("NotifyKeyboardKeysym", &(&self.session, Options::new(), key, u32::from(pressed)))
            .await
            .map_err(denied)
    }

    async fn verifier(&self) -> fdo::Result<zbus::Proxy<'_>> {
        if !self.pointer {
            return Err(denied("Pointer consent is required; restart with --consent --pointer"));
        }
        zbus::Proxy::new(self.connection.inner(), "org.gnome.Shell", "/org/sapiens/Blindly/Foreground", "org.sapiens.Blindly.Foreground1")
            .await
            .map_err(denied)
    }

    async fn pointer_verified(&self, pid: u32) -> fdo::Result<()> {
        let valid: bool = self.verifier().await?.call("Pointer", &pid).await.map_err(denied)?;
        if valid { Ok(()) } else { Err(denied("Pointer is outside the verified foreground window")) }
    }
}

#[zbus::interface(name = "org.sapiens.Blindly.Input1")]
impl Input {
    async fn click(&mut self, pid: u32, x: f64, y: f64) -> fdo::Result<()> {
        if !x.is_finite() || !y.is_finite() {
            return Err(fdo::Error::InvalidArgs("Coordinates must be finite".into()));
        }
        let verifier = self.verifier().await?;
        let (valid, dx, dy): (bool, f64, f64) = verifier.call("Point", &(pid, x, y)).await.map_err(denied)?;
        if !valid {
            return Err(denied("Point is outside the verified foreground window"));
        }
        let portal = zbus::Proxy::new(self.connection.inner(), DESKTOP, PORTAL, REMOTE).await.map_err(denied)?;
        portal.call::<_, _, ()>("NotifyPointerMotion", &(&self.session, Options::new(), dx, dy)).await.map_err(denied)?;
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(1);
        let mut previous = (dx, dy);
        let mut motion = (dx, dy);
        let mut motions = 1;
        loop {
            let (valid, dx, dy): (bool, f64, f64) = verifier.call("Point", &(pid, x, y)).await.map_err(denied)?;
            if !valid {
                return Err(denied("Point changed ownership"));
            }
            if dx.abs() <= 0.5 && dy.abs() <= 0.5 {
                break;
            }
            if std::time::Instant::now() >= deadline {
                return Err(denied(format!("Compositor did not reach the requested point (remaining offset {dx}, {dy})")));
            }
            if (dx, dy) != previous && motions < 3 {
                let moved = (previous.0 - dx, previous.1 - dy);
                let ratio = if moved.0.abs() >= moved.1.abs() { motion.0 / moved.0 } else { motion.1 / moved.1 };
                if !ratio.is_finite() || !(0.25..=4.0).contains(&ratio) {
                    return Err(denied("Compositor pointer motion changed unexpectedly"));
                }
                motion = (dx * ratio, dy * ratio);
                portal
                    .call::<_, _, ()>("NotifyPointerMotion", &(&self.session, Options::new(), motion.0, motion.1))
                    .await
                    .map_err(denied)?;
                previous = (dx, dy);
                motions += 1;
            }
            async_io::Timer::after(std::time::Duration::from_millis(10)).await;
        }
        self.pointer_verified(pid).await?;
        portal.call::<_, _, ()>("NotifyPointerButton", &(&self.session, Options::new(), 272i32, 1u32)).await.map_err(denied)?;
        portal.call("NotifyPointerButton", &(&self.session, Options::new(), 272i32, 0u32)).await.map_err(denied)
    }

    async fn scroll(&mut self, pid: u32, direction: &str, amount: i32) -> fdo::Result<()> {
        if !(1..=100).contains(&amount) {
            return Err(fdo::Error::InvalidArgs("Invalid scroll amount".into()));
        }
        let (axis, steps) = match direction {
            "up" => (0u32, -amount),
            "down" => (0, amount),
            "left" => (1, -amount),
            "right" => (1, amount),
            _ => return Err(fdo::Error::InvalidArgs("Invalid scroll direction".into())),
        };
        let portal = zbus::Proxy::new(self.connection.inner(), DESKTOP, PORTAL, REMOTE).await.map_err(denied)?;
        for _ in 0..amount {
            self.pointer_verified(pid).await?;
            portal
                .call::<_, _, ()>("NotifyPointerAxisDiscrete", &(&self.session, Options::new(), axis, steps.signum()))
                .await
                .map_err(denied)?;
        }
        Ok(())
    }

    async fn key(&mut self, pid: u32, keysym: u32, modifiers: Vec<u32>) -> fdo::Result<()> {
        if modifiers.len() > 4
            || modifiers.iter().any(|key| ![0xffe3, 0xffe9, 0xffe1].contains(key))
            || !((0x20..=0x7e).contains(&keysym) || (0xff00..=0xffff).contains(&keysym))
        {
            return Err(fdo::Error::InvalidArgs("Unsupported key".into()));
        }
        self.foreground(pid).await?;
        let mut pressed = vec![];
        let result = async {
            for key in modifiers.into_iter().chain(std::iter::once(keysym)) {
                self.foreground(pid).await?;
                self.event(key as i32, true).await?;
                pressed.push(key as i32);
            }
            Ok(())
        }
        .await;
        let mut released = Ok(());
        for key in pressed.into_iter().rev() {
            if let Err(error) = self.event(key, false).await {
                released = Err(error);
            }
        }
        result.and(released)
    }
}

fn run(pointer: bool) -> zbus::Result<()> {
    let connection = Connection::session()?;
    // Reserve the name before presenting consent; a second helper must not replace it.
    connection.request_name("org.sapiens.Blindly.Input")?;
    let input = Input::consent(connection.clone(), pointer)?;
    let path = input.session.clone();
    let session = Proxy::new(&connection, DESKTOP, path.as_str(), "org.freedesktop.portal.Session")?;
    let mut closed = session.receive_signal("Closed")?;
    connection.object_server().at("/org/sapiens/Blindly/Input", input)?;
    println!("READY keyboard{}", if pointer { " pointer" } else { "" });
    drop(closed.next());
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args != ["--consent"] && args != ["--consent", "--pointer"] {
        eprintln!("Usage: blindly4-input --consent [--pointer]\nRequests temporary input access through the desktop portal.");
        return ExitCode::from(64);
    }
    match run(args.len() == 2) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::from(77)
        }
    }
}
