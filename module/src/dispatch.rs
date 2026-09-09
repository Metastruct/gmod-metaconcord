//! Carries worker results back to Lua.
//!
//! Worker threads must never touch the lua_State, so they push onto this queue
//! and a Think hook installed at load drains it on the main thread. Callbacks
//! are held as registry references and released once their last event is sent.

use gmod::lua::{LuaReference, State};
use std::sync::Mutex;

pub enum Event {
    /// enumerate finished: rows, or the error that stopped it
    Repos(Result<Vec<crate::repos::Repo>, String>),
    GservStdout(String),
    GservStderr(String),
    /// None when srcds's auto-reap took the status before we could read it.
    GservExit(Option<i32>),
    Failed(String),
}

impl Event {
    /// Whether this is the last thing that call will ever say.
    fn is_terminal(&self) -> bool {
        matches!(self, Event::Repos(_) | Event::GservExit(_) | Event::Failed(_))
    }
}

pub struct Pending {
    pub callback: LuaReference,
    pub event: Event,
}

static QUEUE: Mutex<Vec<Pending>> = Mutex::new(Vec::new());

pub fn push(callback: LuaReference, event: Event) {
    QUEUE
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .push(Pending { callback, event });
}

fn take() -> Vec<Pending> {
    std::mem::take(&mut *QUEUE.lock().unwrap_or_else(|e| e.into_inner()))
}

/// Drops everything queued without calling into Lua. Used on close, where the
/// references belong to a state that is going away.
pub fn clear() {
    take();
}

/// Pushes the second argument of the callback, the result.
unsafe fn push_result(lua: State, event: &Event) {
    match event {
        Event::Failed(_) => lua.push_nil(),
        Event::Repos(Err(_)) => lua.push_nil(),
        Event::Repos(Ok(rows)) => {
            lua.create_table(rows.len() as i32, 0);
            for (index, row) in rows.iter().enumerate() {
                lua.create_table(0, 5);

                lua.push_string(&row.repo);
                lua.set_field(-2, lua_string!("repo"));
                lua.push_string(&row.sub);
                lua.set_field(-2, lua_string!("sub"));
                lua.push_string(&row.remote);
                lua.set_field(-2, lua_string!("remote"));
                lua.push_string(&row.wsid);
                lua.set_field(-2, lua_string!("wsid"));
                lua.push_string(&row.branch);
                lua.set_field(-2, lua_string!("branch"));

                lua.raw_seti(-2, index as i32 + 1);
            }
        }
        Event::GservStdout(text) | Event::GservStderr(text) => {
            lua.create_table(0, 2);
            lua.push_string(if matches!(event, Event::GservStdout(_)) {
                "stdout"
            } else {
                "stderr"
            });
            lua.set_field(-2, lua_string!("kind"));
            lua.push_string(text);
            lua.set_field(-2, lua_string!("data"));
        }
        Event::GservExit(code) => {
            lua.create_table(0, 2);
            lua.push_string("exit");
            lua.set_field(-2, lua_string!("kind"));
            // left unset when the status was lost, so the caller judges the
            // run by its output rather than by a code we had to invent
            if let Some(code) = code {
                lua.push_number(*code as f64);
                lua.set_field(-2, lua_string!("code"));
            }
        }
    }
}

/// Called every tick. Invokes each queued callback as `callback(err, result)`
/// under ErrorNoHaltWithStack, so a broken callback cannot take the server out.
#[lua_function]
pub unsafe fn drain(lua: State) -> i32 {
    for pending in take() {
        lua.get_global(lua_string!("ErrorNoHaltWithStack"));
        let error_handler = lua.get_top();

        lua.from_reference(pending.callback);

        match &pending.event {
            Event::Failed(message) | Event::Repos(Err(message)) => {
                lua.push_string(message);
                lua.push_nil();
            }
            event => {
                lua.push_nil();
                push_result(lua, event);
            }
        }

        let _ = lua.pcall(2, 0, error_handler);
        lua.pop();

        if pending.event.is_terminal() {
            lua.dereference(pending.callback);
        }
    }
    0
}

/// hook.Add("Think", "metaconcord.native", drain)
pub unsafe fn install(lua: State) {
    lua.get_global(lua_string!("hook"));
    lua.get_field(-1, lua_string!("Add"));
    lua.push_string("Think");
    lua.push_string("metaconcord.native");
    lua.push_function(drain);
    lua.call(3, 0);
    lua.pop();
}

/// hook.Remove("Think", "metaconcord.native")
pub unsafe fn remove(lua: State) {
    lua.get_global(lua_string!("hook"));
    lua.get_field(-1, lua_string!("Remove"));
    lua.push_string("Think");
    lua.push_string("metaconcord.native");
    lua.call(2, 0);
    lua.pop();
}
