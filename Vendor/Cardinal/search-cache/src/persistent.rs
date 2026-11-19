use crate::{SlabIndex, SlabNode, ThinSlab, name_index::SortedSlabIndices};
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{BufReader, BufWriter, Write},
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    thread::available_parallelism,
    time::Instant,
};
use tracing::info;
use typed_num::Num;

const LSF_VERSION: i64 = 6;

#[derive(Serialize, Deserialize)]
pub struct PersistentStorage {
    pub version: Num<LSF_VERSION>,
    /// The last event id of the cache.
    pub last_event_id: u64,
    /// Root file path of the cache
    pub path: PathBuf,
    /// Ignore paths
    pub ignore_paths: Vec<PathBuf>,
    /// Paths to include even when they fall under an ignored directory.
    pub include_paths: Vec<PathBuf>,
    /// Root index of the slab
    pub slab_root: SlabIndex,
    pub slab: ThinSlab<SlabNode>,
    pub name_index: BTreeMap<Box<str>, SortedSlabIndices>,
    /// The number of rescans emitted before this snapshot.
    pub rescan_count: u64,
}

pub fn read_cache_from_file(path: &Path) -> Result<PersistentStorage> {
    let cache_decode_time = Instant::now();
    let mut bytes = vec![0u8; 4 * 1024];
    let input = File::open(path).context("Failed to open cache file")?;
    let input = zstd::Decoder::new(input).context("Failed to create zstd decoder")?;
    let mut input = BufReader::new(input);
    let storage: PersistentStorage = postcard::from_io((&mut input, &mut bytes))
        .context("Failed to decode cache, maybe the cache is corrupted")?
        .0;
    info!("Cache decode time: {:?}", cache_decode_time.elapsed());
    Ok(storage)
}

pub fn write_cache_to_file(path: &Path, storage: &PersistentStorage) -> Result<()> {
    let cache_encode_time = Instant::now();
    let parent = path.parent().context("Cache path has no parent")?;
    fs::create_dir_all(parent).context("Failed to create cache directory")?;
    // Unique, exclusively-created 0600 file; no predictable temporary symlink.
    let mut temporary = tempfile::Builder::new().prefix(".windownest-index-").tempfile_in(parent)?;
    temporary.as_file().set_permissions(fs::Permissions::from_mode(0o600))?;
    {
        let output = temporary.as_file_mut();
        let mut output = zstd::Encoder::new(output, 6).context("Failed to create zstd encoder")?;
        output
            .multithread(available_parallelism().map(|x| x.get() as u32).unwrap_or(4))
            .context("Failed to create parallel zstd encoder")?;
        let mut output = BufWriter::new(output);
        postcard::to_io(storage, &mut output).context("Failed to encode cache")?;
        output.flush().context("Failed to flush cache")?;
        let encoder = output.into_inner().map_err(|error| error.into_error())?;
        encoder.finish().context("Failed to finish compressed cache")?;
    }
    temporary.persist(path).map_err(|error| error.error).context("Failed to replace cache file")?;
    info!("Cache encode time: {:?}", cache_encode_time.elapsed());
    info!(
        "Cache size: {} MB",
        fs::symlink_metadata(path)
            .context("Failed to get cache file metadata")?
            .len() as f32
            / 1024.
            / 1024.
    );
    Ok(())
}
