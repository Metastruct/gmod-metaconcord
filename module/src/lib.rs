//! Native half of gmod-metaconcord.
//!
//! It exists to hand Lua host information the sandbox cannot reach, already
//! complete: a finished stats sample rather than a file reader, a parsed repo
//! list rather than a directory walker, a validated gserv run rather than a
//! shell. Nothing here touches the Source engine, only the Lua state.
//!
//! The addon owns the `metaconcord` global, so this sits beside it as
//! `metaconcord_native` and init.lua re-homes it as `metaconcord.native`.

#[macro_use]
extern crate gmod;

mod dispatch;
mod gserv;
mod repos;
mod stats;

use gmod::lua::State;
use std::path::PathBuf;

/// `metaconcord.native.Stats()` -> table, or nil + error.
///
/// cpu is a percentage of one core since the previous call, so the first call
/// after a connect reports 0 and the one 5s later is the first real reading.
#[lua_function]
unsafe fn stats(lua: State) -> i32 {
    match stats::sample() {
        Ok(sample) => {
            lua.create_table(0, 5);

            lua.push_number(sample.cpu);
            lua.set_field(-2, lua_string!("cpu"));

            lua.push_number(sample.mem_used as f64);
            lua.set_field(-2, lua_string!("memUsed"));

            lua.push_number(sample.mem_max as f64);
            lua.set_field(-2, lua_string!("memMax"));

            lua.push_number(sample.net_rx);
            lua.set_field(-2, lua_string!("netRx"));

            lua.push_number(sample.net_tx);
            lua.set_field(-2, lua_string!("netTx"));

            1
        }
        Err(err) => {
            lua.push_nil();
            lua.push_string(&err.to_string());
            2
        }
    }
}

/// `metaconcord.native.Repos(callback)`, callback(err, rows).
///
/// Walks $HOME/gserv/repos on a worker thread; the bridge resolves what the
/// rows point at. An optional first argument overrides the root, for testing.
#[lua_function]
unsafe fn repos_fn(lua: State) -> i32 {
    let root = if lua.is_function(1) {
        lua.push_value(1);
        repos::default_root()
    } else {
        let given = PathBuf::from(lua.check_string(1).into_owned());
        lua.check_function(2);
        lua.push_value(2);
        Some(given)
    };
    let callback = lua.reference();

    let Some(root) = root else {
        dispatch::push(callback, dispatch::Event::Failed("HOME is not set".to_owned()));
        return 0;
    };

    std::thread::spawn(move || {
        let result = repos::enumerate(&root).map_err(|err| format!("{}: {err}", root.display()));
        dispatch::push(callback, dispatch::Event::Repos(result));
    });

    0
}

/// `metaconcord.native.Gserv(verb, callback)`.
///
/// callback(err, event) where event is {kind="stdout"|"stderr", data=...} for
/// each line and {kind="exit", code=n} once, last. A rejected verb calls back
/// with an error and never spawns anything.
#[lua_function]
unsafe fn gserv_fn(lua: State) -> i32 {
    let verb = lua.check_string(1).into_owned();
    lua.check_function(2);
    lua.push_value(2);
    let callback = lua.reference();

    let tokens = match gserv::validate(&verb) {
        Ok(tokens) => tokens,
        Err(message) => {
            dispatch::push(callback, dispatch::Event::Failed(message));
            return 0;
        }
    };

    // held for the life of the run, so every caller queues behind whoever got
    // there first instead of pulling the same repos at the same time
    let Some(guard) = gserv::RunGuard::acquire() else {
        dispatch::push(
            callback,
            dispatch::Event::Failed("a gserv run is already in progress".to_owned()),
        );
        return 0;
    };

    std::thread::spawn(move || {
        let _guard = guard;
        let (tx, rx) = std::sync::mpsc::channel();
        let worker = std::thread::spawn(move || gserv::run(tokens, tx));

        let mut answered = false;
        for output in rx {
            let event = match output {
                gserv::Output::Stdout(text) => dispatch::Event::GservStdout(text),
                gserv::Output::Stderr(text) => dispatch::Event::GservStderr(text),
                gserv::Output::Exit(code) => {
                    answered = true;
                    dispatch::Event::GservExit(code)
                }
                gserv::Output::Failed(message) => {
                    answered = true;
                    dispatch::Event::Failed(message)
                }
            };
            dispatch::push(callback, event);
        }
        let panicked = worker.join().is_err();

        // the callback holds lua's "a run is in progress" flag, so it has to be
        // told the run is over even when the worker died without saying so
        if !answered {
            dispatch::push(
                callback,
                dispatch::Event::Failed(if panicked {
                    "gserv failed: the worker panicked".to_owned()
                } else {
                    "gserv ended without reporting a result".to_owned()
                }),
            );
        }
    });

    0
}

#[gmod13_open]
unsafe fn gmod13_open(lua: State) -> i32 {
    stats::reset();
    dispatch::clear();
    dispatch::install(lua);

    lua.create_table(0, 3);

    lua.push_function(stats);
    lua.set_field(-2, lua_string!("Stats"));

    lua.push_function(repos_fn);
    lua.set_field(-2, lua_string!("Repos"));

    lua.push_function(gserv_fn);
    lua.set_field(-2, lua_string!("Gserv"));

    lua.set_global(lua_string!("metaconcord_native"));

    0
}

#[gmod13_close]
unsafe fn gmod13_close(lua: State) -> i32 {
    stats::reset();
    // the references in here belong to a state that is going away
    dispatch::clear();
    dispatch::remove(lua);

    lua.push_nil();
    lua.set_global(lua_string!("metaconcord_native"));

    0
}
