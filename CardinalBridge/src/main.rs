use cardinal_sdk::{EventStream, EventFlag};
use crossbeam_channel::{select, unbounded};
use fswalk::{NodeFileType, WalkData};
use search_cache::{HandleFSEError, SearchCache, SearchOptions};
use search_cancel::CancellationToken;
use serde::Deserialize;
use serde_json::{Value, json};
use std::{io::{self, BufRead, Write}, path::PathBuf, sync::{Mutex, atomic::{AtomicBool, Ordering}}, time::{Duration, Instant}};
use std::os::unix::fs::{MetadataExt, PermissionsExt};

static STOP: AtomicBool = AtomicBool::new(false);
static OUTPUT: Mutex<()> = Mutex::new(());

#[derive(Deserialize)]
struct Request {
    id: u64,
    #[serde(default)] query: String,
    #[serde(default)] limit: Option<usize>,
    #[serde(default)] hidden: bool,
    #[serde(default)] cancel: bool,
    #[serde(default)] refresh: bool,
}
fn emit(value: Value) {
    let _guard = OUTPUT.lock().unwrap();
    let mut out = io::stdout().lock();
    let _ = writeln!(out, "{value}");
    let _ = out.flush();
}
fn main() {
    unsafe { libc::umask(0o077); }
    if let Err(error) = run() { emit(json!({"event":"error", "message":error})); }
}
fn run() -> Result<(), String> {
    let args: Vec<_> = std::env::args().collect();
    let root = PathBuf::from(args.get(1).ok_or("Missing search root")?);
    let cache_path = PathBuf::from(args.get(2).ok_or("Missing cache path")?);
    let parent = cache_path.parent().ok_or("Missing private cache directory")?;
    std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let metadata = std::fs::symlink_metadata(parent).map_err(|e| e.to_string())?;
    if !metadata.is_dir() || metadata.uid() != unsafe { libc::getuid() } {
        return Err("Cache directory must be owned by this user and cannot be a symlink".into());
    }
    std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700)).map_err(|e| e.to_string())?;
    match std::fs::symlink_metadata(&cache_path) {
        Ok(metadata) => {
            if !metadata.is_file() || metadata.uid() != unsafe { libc::getuid() } {
                return Err("Cache must be an ordinary file owned by this user".into());
            }
            std::fs::set_permissions(&cache_path, std::fs::Permissions::from_mode(0o600)).map_err(|e| e.to_string())?;
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.to_string()),
    }
    if !root.is_dir() { return Err("Search location is not an accessible directory".into()); }
    let (request_tx, request_rx) = unbounded();
    std::thread::spawn(move || {
        for line in io::stdin().lock().lines().map_while(Result::ok) {
            match serde_json::from_str::<Request>(&line) {
                Ok(request) => { let token = CancellationToken::new_search(); if request_tx.send((request, token)).is_err() { break; } }
                Err(_) => emit(json!({"event":"error", "message":"Invalid search request"})),
            }
        }
        STOP.store(true, Ordering::Relaxed);
        let _ = CancellationToken::new_search();
    });
    let mut ignore = vec![PathBuf::from("/System/Volumes/Data"), PathBuf::from("/dev"), PathBuf::from("/private/var/vm")];
    if let Some(parent) = cache_path.parent() { ignore.push(parent.to_path_buf()); }
    let include = vec![];
    emit(json!({"event":"loading", "root":root}));
    let cached = SearchCache::try_read_persistent_cache(&root, &cache_path, &ignore, &include, &STOP);
    let restored = cached.is_ok();
    let mut cache = match cached {
        Ok(cache) => cache,
        Err(_) => {
            let walk = WalkData::new(&root, &ignore, &include, false, || STOP.load(Ordering::Relaxed));
            let result = std::thread::scope(|scope| {
                let task = scope.spawn(|| SearchCache::walk_fs_with_walk_data(&walk, &STOP));
                while !task.is_finished() {
                    emit(json!({"event":"indexing", "count":walk.num_files.load(Ordering::Relaxed) + walk.num_dirs.load(Ordering::Relaxed)}));
                    std::thread::sleep(Duration::from_millis(400));
                }
                task.join()
            }).map_err(|_| "The file indexer stopped unexpectedly")?;
            result.ok_or("Indexing cancelled")?
        }
    };
    if STOP.load(Ordering::Relaxed) { return Ok(()); }
    let (event_tx, watcher) = unbounded();
    let ignored_events = ignore.clone();
    let stream = EventStream::new(&[&root.to_string_lossy()], cache.last_event_id(), 0.25, Box::new(move |events| {
        let filtered: Vec<_> = events.into_iter().filter(|event| event.flag.contains(EventFlag::HistoryDone) || !fswalk::should_ignore_path(&event.path, &ignored_events, &[])).collect();
        if !filtered.is_empty() { let _ = event_tx.send(filtered); }
    })).spawn();
    let watching = stream.is_some();
    let watcher = if watching { watcher } else { crossbeam_channel::never() };
    if !watching {
        emit(json!({"event":"watchUnavailable"}));
        if restored { emit(json!({"event":"indexing", "count":0})); cache.rescan(); }
    }
    if let Some(parent) = cache_path.parent() { std::fs::create_dir_all(parent).map_err(|e| e.to_string())?; }
    if !restored {
        emit(json!({"event":"saving", "count":cache.get_total_files()}));
        if let Err(error) = cache.flush_snapshot_to_file(&cache_path) {
            emit(json!({"event":"warning", "message":format!("Index could not be saved: {error}")}));
        }
    }
    emit(json!({"event":"ready", "count":cache.get_total_files(), "restored":restored, "watching":watching}));
    let mut saved = Instant::now();
    let mut dirty = false;
    loop {
        select! {
            recv(request_rx) -> request => {
                let Ok((request, token)) = request else { break };
                if request.cancel || token.is_cancelled().is_none() { continue; }
                if request.refresh {
                    emit(json!({"event":"indexing", "count":0}));
                    cache.rescan();
                    dirty = true;
                    emit(json!({"event":"ready", "count":cache.get_total_files(), "restored":false, "watching":watching}));
                    continue;
                }
                let started = Instant::now();
                let outcome = cache.search_with_options(&request.query, SearchOptions { case_insensitive: true }, token);
                if token.is_cancelled().is_none() { continue; }
                match outcome {
                    Ok(outcome) => if let Some(nodes) = outcome.nodes {
                        let limit = request.limit.unwrap_or(300).clamp(1, 1000);
                        let mut count = 0;
                        let mut selected = Vec::with_capacity(limit);
                        for node in nodes {
                            if token.is_cancelled().is_none() { break; }
                            let Some(path) = cache.node_path(node) else { continue };
                            if !request.hidden && path.components().any(|c| c.as_os_str().to_string_lossy().starts_with('.')) { continue; }
                            count += 1;
                            if selected.len() < limit { selected.push(node); }
                        }
                        if token.is_cancelled().is_none() { continue; }
                        let rows: Vec<_> = cache.expand_file_nodes(&selected).into_iter().map(|node| {
                            let metadata = std::fs::symlink_metadata(&node.path).ok();
                            let is_dir = metadata.as_ref().map(|m| m.is_dir()).unwrap_or(node.metadata.file_type_hint() == NodeFileType::Dir);
                            let modified = metadata.as_ref().and_then(|m| m.modified().ok()).and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_secs());
                            json!({"path":node.path.to_string_lossy(), "directory":is_dir, "size":metadata.as_ref().map(|m| m.len()), "modified":modified})
                        }).collect();
                        emit(json!({"event":"results", "id":request.id, "rows":rows, "total":count, "milliseconds":started.elapsed().as_secs_f64()*1000.0}));
                    },
                    Err(error) => emit(json!({"event":"queryError", "id":request.id, "message":format!("{error}")})),
                }
            }
            recv(watcher) -> events => if let Ok(events) = events {
                match cache.handle_fs_events(events) {
                    Ok(()) => { dirty = true; emit(json!({"event":"updated", "count":cache.get_total_files()})); }
                    Err(HandleFSEError::Rescan) => {
                        emit(json!({"event":"indexing", "count":0}));
                        cache.rescan();
                        dirty = true;
                        emit(json!({"event":"ready", "count":cache.get_total_files(), "restored":false, "watching":watching}));
                    }
                }
            },
            default(Duration::from_secs(2)) => {}
        }
        if STOP.load(Ordering::Relaxed) { break; }
        if dirty && saved.elapsed() > Duration::from_secs(120) {
            if cache.flush_snapshot_to_file(&cache_path).is_ok() { dirty = false; }
            saved = Instant::now();
        }
    }
    if dirty { let _ = cache.flush_snapshot_to_file(&cache_path); }
    Ok(())
}
