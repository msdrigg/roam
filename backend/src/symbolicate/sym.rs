use crate::database::DeviceInfo;
use crate::symbolicate::RoamDebugInfo;
use crate::symbolicate::diagnostics::LogEntry;
use crate::symbolicate::dyld_local_symbols::{DyldLocalSymbols, local_name_applies};
use anyhow::{Context, Result};
use futures::FutureExt as _;
use object::read::macho::{FatArch, MachOFatFile32, MachOFatFile64};
use object::{FileKind, Object};
use samply_symbols::debugid::DebugId;
use samply_symbols::{
    CandidatePathInfo, FileAndPathHelper, FileAndPathHelperResult, FileLocation, FrameDebugInfo,
    FramesLookupResult, LibraryInfo, LookupAddress, OptionallySendFuture, SymbolManager,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fmt::{Display, Write as _};
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Cursor, Read, Seek};
use std::panic::AssertUnwindSafe;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use symbolic_common::Name;
use symbolic_demangle::{Demangle, DemangleOptions};
use uuid::Uuid;

#[derive(Clone)]
pub struct SymbolicationClient {
    symbolication_root: PathBuf,
}

#[derive(Debug, Clone)]
pub struct StoredDsymArchive {
    pub extracted_root: PathBuf,
    pub indexed_debug_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DsymUploadMetadata {
    pub bundle_identifier: String,
    pub app_version: String,
    pub build_version: String,
    pub platform: String,
}

#[derive(Clone)]
pub struct RoamFileAndPathHelper {
    symbolication_root: PathBuf,
    device_uuid: Uuid,
}

impl RoamFileAndPathHelper {
    pub fn new(symbolication_root: PathBuf, device_uuid: Uuid) -> Self {
        RoamFileAndPathHelper {
            symbolication_root,
            device_uuid,
        }
    }

    async fn load_file_impl(
        &self,
        location: RoamFileLocation,
    ) -> FileAndPathHelperResult<memmap2::Mmap> {
        let file = File::open(&location.path)?;
        Ok(unsafe { memmap2::MmapOptions::new().map(&file)? })
    }

    fn expand_library_info(&self, library_info: &mut LibraryInfo) {
        let _ = library_info;
    }
}
#[derive(Debug, Clone)]
pub struct RoamFileLocation {
    path: PathBuf,
    device_uuid: Uuid,
    symbolicate_root: PathBuf,
}

impl Display for RoamFileLocation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.path.display())
    }
}

impl RoamFileLocation {
    fn with_path(&self, path: PathBuf) -> Self {
        Self {
            device_uuid: self.device_uuid,
            path,
            symbolicate_root: self.symbolicate_root.clone(),
        }
    }

    fn device_path(&self) -> PathBuf {
        self.symbolicate_root.join(self.device_uuid.to_string())
    }
}

impl FileLocation for RoamFileLocation {
    fn location_for_dyld_subcache(&self, suffix: &str) -> Option<Self> {
        // samply-symbols asks for ".N" / ".0N", but macOS 13+ caches store each
        // subcache with a typed suffix (e.g. ".02.dylddata"). If the bare path
        // is missing, fall back to the typed variants so the V2 layout loads.
        let base = self.path.file_name().unwrap().to_owned();
        let mut bare = base.clone();
        bare.push(suffix);
        let bare_path = self.path.with_file_name(&bare);
        if bare_path.exists() || !suffix.starts_with('.') || suffix == ".symbols" {
            return Some(self.with_path(bare_path));
        }
        for type_suffix in [".dylddata", ".dyldreadonly", ".dyldlinkedit"] {
            let mut typed = base.clone();
            typed.push(suffix);
            typed.push(type_suffix);
            let typed_path = self.path.with_file_name(typed);
            if typed_path.exists() {
                return Some(self.with_path(typed_path));
            }
        }
        Some(self.with_path(bare_path))
    }

    fn location_for_external_object_file(&self, object_file: &str) -> Option<Self> {
        // External object files are referred to by absolute file path, so we only
        // load them if those paths were found in a local file.
        let obj_path = self.device_path().join(object_file);
        Some(self.with_path(obj_path))
    }

    fn location_for_pdb_from_binary(&self, pdb_path_in_binary: &str) -> Option<Self> {
        // We only respect absolute paths to PDB files if those paths were found in a local binary.
        let obj_path = self.device_path().join(pdb_path_in_binary);
        Some(self.with_path(obj_path))
    }

    fn location_for_source_file(&self, source_file_path: &str) -> Option<Self> {
        let debug_file_path = &self.path;
        if source_file_path.starts_with("https://") || source_file_path.starts_with("http://") {
            // Treat the path as a URL. One case where we get URLs is in jitdump files:
            // E.g. profiling a browser which executes JITted JS code from a script on
            // the web will create a jitdump file where the debug information for an
            // address has a URL as the file path.
            return None;
        }
        let source_file_path = Path::new(source_file_path);

        if source_file_path.is_absolute() {
            Some(self.with_path(self.device_path().join(source_file_path)))
        } else {
            // Resolve relative paths with respect to the location of the debug file.
            debug_file_path
                .parent()
                .map(|base_path| self.with_path(base_path.join(source_file_path)))
        }
    }

    fn location_for_breakpad_symindex(&self) -> Option<Self> {
        None
    }

    fn location_for_dwo(&self, comp_dir: &str, path: &str) -> Option<Self> {
        let debug_file_path = &self.path;
        if path.starts_with('/') {
            return Some(self.with_path(self.device_path().join(path)));
        }
        // Resolve relative paths with respect to comp_dir.
        if comp_dir.starts_with('/') {
            let comp_dir = comp_dir.trim_end_matches('/');
            let dwo_path = format!("{comp_dir}/{path}");
            return Some(self.with_path(self.device_path().join(&dwo_path)));
        }
        // Resolve relative paths with respect to the location of the debug file.
        debug_file_path
            .parent()
            .map(|base_path| self.with_path(base_path.join(comp_dir).join(path)))
    }

    fn location_for_dwp(&self) -> Option<Self> {
        // DWP files are only used locally; by convention they are named
        // "<binaryname>.dwp" and placed next to the corresponding binary.
        // The original binary does not have a pointer to the DWP file.
        // DWP files also do not have a build ID, they cannot be looked up
        // from a symbol server. The debug information inside a DWP file is
        // only useful in combination with the debug info inside the binary
        // (the "skeleton units"); a DWP file by itself cannot be used to
        // look up symbols if the binary has been stripped of debug info.
        let binary_path = &self.path;
        let mut dwp_path = binary_path.as_os_str().to_os_string();
        dwp_path.push(".dwp");
        Some(self.with_path(dwp_path.into()))
    }
}

impl FileAndPathHelper for RoamFileAndPathHelper {
    type F = memmap2::Mmap;
    type FL = RoamFileLocation;

    fn get_candidate_paths_for_debug_file(
        &self,
        library_info: &LibraryInfo,
    ) -> FileAndPathHelperResult<Vec<CandidatePathInfo<RoamFileLocation>>> {
        let mut library_info = library_info.clone();
        self.expand_library_info(&mut library_info);

        let Some(debug_id) = library_info.debug_id else {
            tracing::warn!(?library_info, "No debug ID found for library");
            return Err(Box::new(
                samply_symbols::Error::NotEnoughInformationToIdentifyBinary,
            ));
        };

        let mut options = Vec::new();
        let breakpad_id = debug_id.breakpad().to_string();
        let uuid = debug_id.uuid().to_string().to_ascii_uppercase();

        for path in [
            self.symbolication_root
                .join("cache")
                .join("by-debug-id")
                .join(&breakpad_id),
            self.symbolication_root
                .join("cache")
                .join("by-uuid")
                .join(&uuid),
        ] {
            if path.exists() {
                options.push(CandidatePathInfo::SingleFile(RoamFileLocation {
                    path,
                    device_uuid: self.device_uuid,
                    symbolicate_root: self.symbolication_root.clone(),
                }));
            }
        }

        if options.is_empty() {
            tracing::warn!(?library_info, %breakpad_id, "No local dSYM candidate found");
        }

        let dylib_paths = likely_dylib_paths(&library_info);
        let leaf_name = library_info
            .name
            .as_deref()
            .or(library_info.debug_name.as_deref());
        if !dylib_paths.is_empty() {
            for dyld_cache_path in self.get_dyld_shared_cache_paths(library_info.arch.as_deref())? {
                for dylib_path in
                    resolve_dylib_paths_in_cache(&dyld_cache_path.path, leaf_name, &dylib_paths)
                {
                    options.push(CandidatePathInfo::InDyldCache {
                        dyld_cache_path: dyld_cache_path.clone(),
                        dylib_path,
                    });
                }
            }
        }

        Ok(options)
    }

    fn get_candidate_paths_for_binary(
        &self,
        library_info: &LibraryInfo,
    ) -> FileAndPathHelperResult<Vec<CandidatePathInfo<RoamFileLocation>>> {
        self.get_candidate_paths_for_debug_file(library_info)
    }

    fn get_dyld_shared_cache_paths(
        &self,
        arch: Option<&str>,
    ) -> FileAndPathHelperResult<Vec<RoamFileLocation>> {
        let mut vec = Vec::new();

        let mut add_entries_in_dir = |dir: PathBuf| {
            let mut add_entry_for_arch = |arch: &str| {
                let path = dir.join(format!("dyld_shared_cache_{arch}"));
                if !path.exists() {
                    return;
                }
                vec.push(RoamFileLocation {
                    path,
                    device_uuid: self.device_uuid,
                    symbolicate_root: self.symbolication_root.clone(),
                });
            };
            match arch {
                None => {
                    // Try all known architectures.
                    add_entry_for_arch("arm64e");
                    add_entry_for_arch("x86_64h");
                    add_entry_for_arch("x86_64");
                }
                Some("x86_64") => {
                    // x86_64 binaries can be either in the x86_64 or in the x86_64h cache.
                    add_entry_for_arch("x86_64h");
                    add_entry_for_arch("x86_64");
                }
                Some(arch) => {
                    // Use the cache that matches the CPU architecture of the object file.
                    add_entry_for_arch(arch);
                }
            }
        };

        let system_root = self.symbolication_root.join("system");
        if let Ok(devices) = fs::read_dir(system_root) {
            for device in devices.flatten() {
                if let Ok(builds) = fs::read_dir(device.path()) {
                    for build in builds.flatten() {
                        let dyld_dir = build.path().join("dyld");
                        normalize_dyld_dir(&dyld_dir);
                        add_entries_in_dir(dyld_dir);
                    }
                }
            }
        }

        add_entries_in_dir(PathBuf::from(
            "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld",
        ));

        Ok(vec)
    }

    fn load_file(
        &self,
        location: RoamFileLocation,
    ) -> std::pin::Pin<Box<dyn OptionallySendFuture<Output = FileAndPathHelperResult<Self::F>> + '_>>
    {
        Box::pin(self.load_file_impl(location))
    }
}

pub struct AddressResult {
    pub symbol_name: String,
    pub inline_frames: Option<Vec<FrameDebugInfo>>,
}

pub type AddressResults = BTreeMap<u32, Option<AddressResult>>;

pub struct LookedUpAddresses {
    pub address_results: AddressResults,
    pub symbol_count: u32,
}

#[derive(Debug, Default)]
struct SymbolicationRequest {
    addresses: Vec<u32>,
    binary_names: BTreeSet<String>,
}

impl SymbolicationRequest {
    fn add(&mut self, address: u32, binary_name: Option<&str>) {
        self.addresses.push(address);
        if let Some(binary_name) = binary_name {
            self.binary_names.insert(binary_name.to_string());
        }
    }
}

impl LookedUpAddresses {
    pub fn for_addresses(addresses: &[u32]) -> Self {
        LookedUpAddresses {
            address_results: addresses.iter().map(|&addr| (addr, None)).collect(),
            symbol_count: 0,
        }
    }

    pub fn add_address_symbol(&mut self, address: u32, symbol_name: String) {
        *self.address_results.get_mut(&address).unwrap() = Some(AddressResult {
            symbol_name,
            inline_frames: None,
        });
    }

    pub fn add_address_debug_info(&mut self, address: u32, frames: Vec<FrameDebugInfo>) {
        let outer_function_name = frames.last().and_then(|f| f.function.as_deref());
        let entry = self.address_results.get_mut(&address).unwrap();

        match entry {
            Some(address_result) => {
                // Overwrite the symbol name with the function name from the debug info.
                if let Some(name) = outer_function_name {
                    address_result.symbol_name = name.to_string();
                }
                // Add the inline frame info.``
                address_result.inline_frames = Some(frames);
            }
            None => {
                // add_address_symbol has not been called for this address.
                // This happens when we only have debug info but no symbol for this address.
                // This is a rare case.
                *entry = Some(AddressResult {
                    symbol_name: outer_function_name
                        .map_or_else(|| format!("0x{address:x}"), str::to_string),
                    inline_frames: Some(frames),
                });
            }
        }
    }

    pub fn set_total_symbol_count(&mut self, total_symbol_count: u32) {
        self.symbol_count = total_symbol_count;
    }
}

impl SymbolicationClient {
    pub fn new(symbolication_root: PathBuf) -> Self {
        SymbolicationClient {
            symbolication_root: symbolication_root.clone(),
        }
    }

    /// Root directory holding `cache/by-uuid/`, `cache/by-debug-id/`, `system/`,
    /// and `uploads/`. Exposed so HTTP handlers can stream dSYMs out of the
    /// by-uuid cache directly.
    pub fn root(&self) -> &Path {
        &self.symbolication_root
    }

    /// Resolves the cached dSYM path for a given binary UUID (uppercase hex with
    /// dashes). The path may be a symlink (Unix) created by `index_debug_file`.
    /// Returns `None` if the UUID doesn't exist in the cache.
    pub fn dsym_path_for_uuid(&self, uuid: &str) -> Option<PathBuf> {
        let path = self
            .symbolication_root
            .join("cache")
            .join("by-uuid")
            .join(uuid.to_ascii_uppercase());
        path.exists().then_some(path)
    }

    /// Adds a dSYM into both the `by-uuid` and `by-debug-id` caches, mirroring
    /// the layout produced when uploading a dSYM zip via the server.
    pub fn index_dsym_file(&self, uuid: &str, breakpad_id: &str, source: &Path) -> Result<()> {
        let by_uuid = self
            .symbolication_root
            .join("cache")
            .join("by-uuid")
            .join(uuid.to_ascii_uppercase());
        let by_debug_id = self
            .symbolication_root
            .join("cache")
            .join("by-debug-id")
            .join(breakpad_id);
        link_or_copy_debug_file(source, &by_uuid)?;
        link_or_copy_debug_file(source, &by_debug_id)?;
        Ok(())
    }

    async fn symbolicate_requested_addresses_for_lib(
        &self,
        breakpad_id: &str,
        request: SymbolicationRequest,
        symbol_manager: &SymbolManager<impl FileAndPathHelper>,
    ) -> Result<LookedUpAddresses, samply_symbols::Error> {
        let mut addresses = request.addresses;
        // Sort the addresses before the lookup, to have a higher chance of hitting
        // the same external file for subsequent addresses.
        addresses.sort_unstable();
        addresses.dedup();

        // Only accept breakpad IDs with the right syntax, and which aren't all-zeros.
        let debug_id = match DebugId::from_breakpad(breakpad_id) {
            Ok(debug_id) if !debug_id.is_nil() => Ok(debug_id),
            _ => Err(samply_symbols::Error::InvalidBreakpadId(
                breakpad_id.to_string(),
            )),
        }?;

        let mut symbolication_result = LookedUpAddresses::for_addresses(&addresses);
        let mut external_addresses = Vec::new();

        // Do the synchronous work first, and accumulate external_addresses which need
        // to be handled asynchronously. This allows us to group async file loads by
        // the external file.

        let binary_name = request.binary_names.iter().next().cloned();
        let info = LibraryInfo {
            debug_name: binary_name.clone(),
            debug_id: Some(debug_id),
            name: binary_name,
            ..Default::default()
        };
        let symbol_map = symbol_manager.load_symbol_map(&info).await?;

        symbolication_result.set_total_symbol_count(symbol_map.symbol_count() as u32);

        for &address in &addresses {
            if let Some(address_info) = symbol_map.lookup_sync(LookupAddress::Relative(address)) {
                symbolication_result.add_address_symbol(address, address_info.symbol.name);
                match address_info.frames {
                    Some(FramesLookupResult::Available(frames)) => {
                        symbolication_result.add_address_debug_info(address, frames)
                    }
                    Some(FramesLookupResult::External(ext_address)) => {
                        external_addresses.push((address, ext_address));
                    }
                    None => {}
                }
            }
        }

        // Look up any addresses whose debug info is in an external file.
        // The symbol_map caches the most recent external file, so we sort our
        // external addresses by ExternalFileAddressRef before we do the lookup,
        // in order to get the best hit rate in lookup_external.
        external_addresses.sort_unstable_by(|(_, a), (_, b)| a.cmp(b));

        for (address, ext_address) in external_addresses {
            if let Some(frames) = symbol_map.lookup_external(&ext_address).await {
                symbolication_result.add_address_debug_info(address, frames);
            }
        }

        Ok(symbolication_result)
    }
}

impl SymbolicationClient {
    pub async fn store_dsym_zip_with_metadata(
        &self,
        metadata: Option<DsymUploadMetadata>,
        dsym_zip: Vec<u8>,
    ) -> Result<StoredDsymArchive> {
        let symbolication_root = self.symbolication_root.clone();
        tokio::task::spawn_blocking(move || {
            Self::store_dsym_zip_blocking(symbolication_root, metadata, Cursor::new(dsym_zip))
        })
        .await
        .context("joining dSYM zip extraction task")?
    }

    /// Extracts a dSYM zip that has already been streamed to disk. Preferred over
    /// [`Self::store_dsym_zip_with_metadata`] for uploads: dSYM archives run to
    /// hundreds of megabytes and buffering one in memory OOM-kills small machines.
    pub async fn store_dsym_zip_file_with_metadata(
        &self,
        metadata: Option<DsymUploadMetadata>,
        zip_path: PathBuf,
    ) -> Result<StoredDsymArchive> {
        let symbolication_root = self.symbolication_root.clone();
        tokio::task::spawn_blocking(move || {
            let file = File::open(&zip_path)
                .with_context(|| format!("opening uploaded dSYM zip {}", zip_path.display()))?;
            Self::store_dsym_zip_blocking(symbolication_root, metadata, BufReader::new(file))
        })
        .await
        .context("joining dSYM zip extraction task")?
    }

    fn store_dsym_zip_blocking<R: Read + Seek>(
        symbolication_root: PathBuf,
        metadata: Option<DsymUploadMetadata>,
        dsym_zip: R,
    ) -> Result<StoredDsymArchive> {
        let mut extracted_root = symbolication_root.join("uploads");
        if let Some(metadata) = &metadata {
            extracted_root = extracted_root
                .join(sanitize_cache_component(&metadata.bundle_identifier))
                .join(sanitize_cache_component(&metadata.platform))
                .join(sanitize_cache_component(&metadata.build_version))
                .join(Uuid::new_v4().to_string());
        } else {
            extracted_root = extracted_root.join(Uuid::new_v4().to_string());
        }

        fs::create_dir_all(&extracted_root).with_context(|| {
            format!(
                "creating dSYM extraction directory {}",
                extracted_root.display()
            )
        })?;
        if let Some(metadata) = &metadata {
            let metadata_json =
                serde_json::to_vec_pretty(metadata).context("serializing dSYM upload metadata")?;
            fs::write(extracted_root.join("metadata.json"), metadata_json).with_context(|| {
                format!(
                    "writing dSYM upload metadata in {}",
                    extracted_root.display()
                )
            })?;
        }

        extract_zip_archive(dsym_zip, &extracted_root)?;

        let dwarf_files = find_dwarf_files(&extracted_root)?;
        if dwarf_files.is_empty() {
            anyhow::bail!(
                "uploaded archive did not contain any .dSYM/Contents/Resources/DWARF files"
            );
        }

        let mut indexed_debug_ids = Vec::new();
        for dwarf_file in dwarf_files {
            let debug_ids = debug_ids_for_macho(&dwarf_file)
                .with_context(|| format!("reading Mach-O UUIDs from {}", dwarf_file.display()))?;
            for debug_id in debug_ids {
                index_debug_file(&symbolication_root, debug_id, &dwarf_file)?;
                indexed_debug_ids.push(debug_id.breakpad().to_string());
            }
        }

        indexed_debug_ids.sort();
        indexed_debug_ids.dedup();
        if indexed_debug_ids.is_empty() {
            anyhow::bail!("uploaded dSYM archive did not contain any Mach-O UUIDs");
        }

        Ok(StoredDsymArchive {
            extracted_root,
            indexed_debug_ids,
        })
    }

    async fn ensure_system_symbols_cached(&self, payload: &MetricKitPayload) -> Result<()> {
        let Some(requirement) = payload.system_symbol_requirement() else {
            tracing::info!(
                "Payload has no deviceType/osVersion metadata; skipping system symbol fetch"
            );
            return Ok(());
        };

        let dyld_dir = self
            .symbolication_root
            .join("system")
            .join(&requirement.device_type)
            .join(&requirement.build_id)
            .join("dyld");
        // `<device>/<build>` is the eviction unit; the arch-specific caches live
        // one level below it.
        let cache_entry_dir = dyld_dir.parent().unwrap_or(&dyld_dir).to_path_buf();

        if dyld_cache_exists(&dyld_dir, requirement.arch.as_deref()).await? {
            tracing::info!(
                device_type = %requirement.device_type,
                build_id = %requirement.build_id,
                arch = requirement.arch.as_deref().unwrap_or("--"),
                "System dyld_shared_cache already cached"
            );
            touch_last_used(&cache_entry_dir);
            return Ok(());
        }

        // One download per cache. Concurrent `ipsw` runs for the same build
        // share a FUSE mountpoint and clobber each other, so serialize on the
        // cache identity and re-check afterwards.
        let cache_key = format!(
            "{}/{}/{}",
            requirement.device_type,
            requirement.build_id,
            requirement.arch.as_deref().unwrap_or("--")
        );
        let gate = download_gate(&cache_key);
        let _guard = gate.lock().await;

        if dyld_cache_exists(&dyld_dir, requirement.arch.as_deref()).await? {
            tracing::info!(
                device_type = %requirement.device_type,
                build_id = %requirement.build_id,
                "System dyld_shared_cache downloaded by a concurrent payload"
            );
            touch_last_used(&cache_entry_dir);
            return Ok(());
        }

        tracing::info!(
            device_type = %requirement.device_type,
            build_id = %requirement.build_id,
            arch = requirement.arch.as_deref().unwrap_or("--"),
            os_family = requirement.os_family.as_deref().unwrap_or("--"),
            "Downloading system dyld_shared_cache via ipsw"
        );

        // Anything here is debris from an unfinished download; a complete one
        // would have satisfied `dyld_cache_exists` above. Clear it so `ipsw`
        // cannot mistake a truncated file for one it already fetched.
        if let Err(err) = tokio::fs::remove_dir_all(&dyld_dir).await
            && err.kind() != std::io::ErrorKind::NotFound
        {
            tracing::warn!(
                ?err,
                dir = %dyld_dir.display(),
                "Could not clear an incomplete dyld cache before re-downloading"
            );
        }

        tokio::fs::create_dir_all(&dyld_dir)
            .await
            .with_context(|| format!("creating dyld cache directory {}", dyld_dir.display()))?;

        let started = std::time::Instant::now();
        let outcome = extract_dyld_shared_cache(
            &requirement.device_type,
            &requirement.build_id,
            &dyld_dir,
            requirement.arch.as_deref(),
            requirement.os_family.as_deref(),
        )
        .await;

        // `ipsw` exits 0 having written nothing when a source has no match for
        // the build, so success has to mean a cache is actually on disk.
        let outcome = match outcome {
            Ok(()) => match dyld_cache_exists(&dyld_dir, requirement.arch.as_deref()).await {
                Ok(true) => Ok(()),
                Ok(false) => Err(anyhow::anyhow!(
                    "ipsw exited successfully but left no dyld_shared_cache in {}",
                    dyld_dir.display()
                )),
                Err(err) => Err(err.context("checking for the downloaded dyld_shared_cache")),
            },
            Err(err) => Err(err),
        };

        // `dyld_cache_exists` only looks for a `dyld_shared_cache*` name, so a
        // cache truncated mid-copy would read as present forever. Clear it.
        if let Err(err) = outcome {
            if let Err(remove_err) = tokio::fs::remove_dir_all(&cache_entry_dir).await {
                tracing::warn!(
                    ?remove_err,
                    dir = %cache_entry_dir.display(),
                    "Could not remove partial dyld cache after a failed download"
                );
            }
            return Err(err);
        }

        normalize_dyld_dir(&dyld_dir);
        touch_last_used(&cache_entry_dir);
        tracing::info!(
            device_type = %requirement.device_type,
            build_id = %requirement.build_id,
            elapsed_ms = started.elapsed().as_millis() as u64,
            "Downloaded system dyld_shared_cache"
        );

        // Evict only after a successful download: that is the only moment the
        // cache grows, and it guarantees the entry we just paid for is the most
        // recently used, so it is never the one dropped.
        enforce_system_cache_budget(
            &self.symbolication_root.join("system"),
            &cache_entry_dir,
            system_cache_budget(),
        )
        .await;

        Ok(())
    }
}

impl SymbolicationClient {
    fn collect_symbolication_requests(
        frame: &MetricKitCallStackFrame,
        requests: &mut BTreeMap<String, SymbolicationRequest>,
    ) {
        for_each_frame(std::slice::from_ref(frame), |frame| {
            if let (Some(binary_uuid), Some(offset)) = (
                frame.binary_uuid.as_deref(),
                frame.offset_into_binary_text_segment,
            ) && let Some(breakpad_id) = binary_uuid_to_breakpad_id(binary_uuid)
                && let Ok(offset) = u32::try_from(offset)
            {
                requests
                    .entry(breakpad_id)
                    .or_default()
                    .add(offset, frame.binary_name.as_deref());
            }
        });
    }

    pub async fn symbolicate_diagnostics(
        &self,
        diagnostics: &RoamDebugInfo,
        installation_info: &DeviceInfo,
        metrics_payload: &Path,
    ) -> Result<PathBuf, anyhow::Error> {
        let started = std::time::Instant::now();
        tracing::info!(payload = %metrics_payload.display(), "Starting symbolication");

        let mut report_path = PathBuf::from(metrics_payload);
        let mut new_filename = report_path
            .file_name()
            .map(|x| x.to_os_string())
            .unwrap_or_else(|| "unknown-payload".into());
        new_filename.push(".symbolicated");
        report_path.set_file_name(new_filename);

        let payload_bytes = tokio::fs::read(metrics_payload)
            .await
            .with_context(|| format!("reading MetricKit payload {}", metrics_payload.display()))?;
        let payload = parse_metrickit_payload(&payload_bytes)
            .with_context(|| format!("parsing MetricKit payload {}", metrics_payload.display()))?;
        tracing::info!(
            payload_bytes = payload_bytes.len(),
            crash_diagnostics = payload.crash_diagnostics.len(),
            hang_diagnostics = payload.hang_diagnostics.len(),
            "Parsed MetricKit payload"
        );

        // Kept rather than just logged: whether the system symbol source was
        // reachable decides, further down, if a report that resolved nothing is
        // worth retrying or is simply missing a dSYM we will never have.
        let system_symbols_error = match self.ensure_system_symbols_cached(&payload).await {
            Ok(()) => None,
            Err(error) => {
                tracing::warn!(?error, "Could not prepare IPSW/dyld shared cache symbols");
                Some(format!("{error:#}"))
            }
        };

        let mut requests = BTreeMap::new();
        for crash in payload.diagnostics() {
            for call_stack in &crash.call_stack_tree.call_stacks {
                for frame in &call_stack.call_stack_root_frames {
                    Self::collect_symbolication_requests(frame, &mut requests);
                }
            }
        }
        let total_addresses: usize = requests.values().map(|r| r.addresses.len()).sum();
        tracing::info!(
            unique_binaries = requests.len(),
            total_addresses,
            "Collected symbolication requests"
        );

        let symbol_manager = samply_symbols::SymbolManager::with_helper(
            RoamFileAndPathHelper::new(self.symbolication_root.clone(), Uuid::nil()),
        );
        let mut symbolicated_addresses = BTreeMap::new();
        let mut lookup_errors = BTreeMap::new();
        let mut resolved_addresses = 0usize;
        for (breakpad_id, request) in requests {
            let address_count = request.addresses.len();
            let binary_name = request
                .binary_names
                .iter()
                .next()
                .cloned()
                .unwrap_or_default();
            tracing::info!(
                %breakpad_id,
                binary_name = %binary_name,
                address_count,
                "Looking up symbols for binary"
            );
            let lib_started = std::time::Instant::now();
            // The object/DWARF readers can panic on layouts they did not
            // anticipate, and we do not control the binaries. Treat a panic as a
            // lookup error so one bad binary cannot lose the whole report.
            let outcome = match AssertUnwindSafe(self.symbolicate_requested_addresses_for_lib(
                &breakpad_id,
                request,
                &symbol_manager,
            ))
            .catch_unwind()
            .await
            {
                Ok(Ok(result)) => Ok(result),
                Ok(Err(err)) => {
                    tracing::warn!(%breakpad_id, error = ?err, "Could not symbolicate binary UUID");
                    Err(err.to_string())
                }
                Err(panic) => {
                    let message = describe_panic(&*panic);
                    tracing::error!(
                        %breakpad_id,
                        binary_name = %binary_name,
                        panic = %message,
                        "Symbol lookup panicked; treating this binary as unresolved"
                    );
                    Err(format!("symbol lookup panicked: {message}"))
                }
            };
            match outcome {
                Ok(result) => {
                    let resolved = result
                        .address_results
                        .values()
                        .filter(|v| v.is_some())
                        .count();
                    tracing::info!(
                        %breakpad_id,
                        resolved,
                        total = address_count,
                        symbol_count = result.symbol_count,
                        elapsed_ms = lib_started.elapsed().as_millis() as u64,
                        "Symbolicated binary"
                    );
                    resolved_addresses += resolved;
                    symbolicated_addresses.insert(breakpad_id, result);
                }
                Err(message) => {
                    lookup_errors.insert(breakpad_id, message);
                }
            }
        }

        if let Some(requirement) = payload.system_symbol_requirement() {
            let dyld_dir = self
                .symbolication_root
                .join("system")
                .join(&requirement.device_type)
                .join(&requirement.build_id)
                .join("dyld");
            let arch = requirement.arch.clone();
            let taken = std::mem::take(&mut symbolicated_addresses);
            let (restored, named) = tokio::task::spawn_blocking(move || {
                let mut results = taken;
                let named = apply_local_symbols(&dyld_dir, arch.as_deref(), &mut results);
                (results, named)
            })
            .await
            .context("local symbol lookup task panicked")?;
            symbolicated_addresses = restored;
            match named {
                Ok(0) => {}
                Ok(count) => tracing::info!(count, "Named frames from dyld local symbols"),
                Err(error) => tracing::warn!(?error, "Could not read dyld local symbols"),
            }
        }

        let mut report = render_metric_report(
            diagnostics,
            installation_info,
            &payload,
            &symbolicated_addresses,
            &lookup_errors,
        )?;

        // A report where nothing resolved is a wall of hex, so say so at the
        // top rather than letting it pass for a normal report.
        if total_addresses > 0 && resolved_addresses == 0 {
            let mut banner = String::from(
                "!! NO SYMBOLS RESOLVED - every address in this report is unsymbolicated.\n",
            );
            match &system_symbols_error {
                Some(error) => {
                    let _ = writeln!(banner, "!! System symbol source unavailable: {error}");
                    let _ = writeln!(
                        banner,
                        "!! This is usually transient (rate limiting); the payload will be retried."
                    );
                }
                None => {
                    let _ = writeln!(
                        banner,
                        "!! No dSYM on file for the binaries below - upload it and re-symbolicate."
                    );
                }
            }
            banner.push('\n');
            report.insert_str(0, &banner);
        }

        tokio::fs::write(&report_path, &report)
            .await
            .with_context(|| format!("writing symbolicated report {}", report_path.display()))?;
        tracing::info!(
            report = %report_path.display(),
            report_bytes = report.len(),
            resolved_binaries = symbolicated_addresses.len(),
            unresolved_binaries = lookup_errors.len(),
            resolved_addresses,
            total_addresses,
            elapsed_ms = started.elapsed().as_millis() as u64,
            "Wrote symbolicated report"
        );

        // Nothing resolved plus an unreachable system source means the inputs
        // were missing, which usually clears on retry, so fail and back off. A
        // missing dSYM will not fix itself, so that report ships with a banner.
        if total_addresses > 0 && resolved_addresses == 0 {
            if let Some(error) = system_symbols_error {
                anyhow::bail!(
                    "symbolicated 0 of {total_addresses} addresses and the system symbol \
                     source was unavailable ({error}); retrying rather than posting an \
                     unsymbolicated report"
                );
            }
            tracing::error!(
                total_addresses,
                unresolved_binaries = lookup_errors.len(),
                "Report resolved no addresses; delivering with a no-symbols banner"
            );
        }

        Ok(report_path)
    }
}

/// Stack budget for the payload parse thread.
///
/// serde_json recurses once per nesting level, so lifting the depth cap turns a
/// clean parse error into a stack overflow. This clears far more frames than
/// MetricKit emits for a runaway recursion, and costs address space rather than
/// memory since pages commit only as the parser touches them.
///
/// Linux overcommit refuses a mapping larger than RAM, so the reservation fails
/// on the 256 MB backend VM. Only the worker may call
/// `parse_metrickit_payload`; the backend uses `scan_binary_uuids` instead.
const PAYLOAD_PARSE_STACK_SIZE: usize = 256 * 1024 * 1024;

/// Collect `binaryUUID` values straight out of the raw payload bytes.
///
/// Ingest needs the UUID list to tell a leasing worker which dSYMs it holds,
/// but runs on a 256 MB VM that cannot map `parse_metrickit_payload`'s stack.
/// This is a flat forward scan over bytes already in memory.
///
/// A hint rather than a parse: the worker re-derives the authoritative set, so
/// a missed UUID costs a dSYM pre-fetch, not a symbol.
pub(crate) fn scan_binary_uuids(bytes: &[u8]) -> BTreeSet<String> {
    const KEY: &[u8] = b"\"binaryUUID\"";

    let mut out = BTreeSet::new();
    let mut cursor = 0usize;

    while let Some(found) = find_subslice(&bytes[cursor..], KEY) {
        let after_key = cursor + found + KEY.len();
        cursor = after_key;

        // Expect `: "<uuid>"`, allowing arbitrary whitespace either side of the
        // colon - MetricKit pretty-prints with a space, but nothing guarantees
        // it and a compact payload must still scan.
        let rest = &bytes[after_key..];
        let Some(colon) = rest.iter().position(|b| !b.is_ascii_whitespace()) else {
            break;
        };
        if rest[colon] != b':' {
            continue;
        }
        let Some(quote) = rest[colon + 1..]
            .iter()
            .position(|b| !b.is_ascii_whitespace())
            .filter(|offset| rest[colon + 1 + offset] == b'"')
        else {
            continue;
        };
        let value_start = colon + 1 + quote + 1;
        let Some(len) = rest[value_start..].iter().position(|b| *b == b'"') else {
            break;
        };
        cursor = after_key + value_start + len + 1;

        if let Ok(uuid) = std::str::from_utf8(&rest[value_start..value_start + len]) {
            // Same shape filter the parsed path applies, so a stray string keyed
            // "binaryUUID" somewhere in the payload cannot enter the hint set.
            if binary_uuid_to_breakpad_id(uuid).is_some() {
                out.insert(uuid.to_string());
            }
        }
    }

    out
}

fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

/// Parse a MetricKit payload with serde_json's recursion cap lifted.
///
/// MetricKit nests one JSON level per stack frame, so the default 128-deep cap
/// rejected exactly the deep stacks a stack overflow produces.
///
/// `disable_recursion_limit` removes serde_json's own depth guard, so the parse
/// runs on an oversized stack. Walkers over the tree are iterative (see
/// `for_each_frame`), so depth then costs heap rather than stack.
pub(crate) fn parse_metrickit_payload(bytes: &[u8]) -> Result<MetricKitPayload, serde_json::Error> {
    std::thread::scope(|scope| {
        let handle = std::thread::Builder::new()
            .name("metrickit-parse".into())
            .stack_size(PAYLOAD_PARSE_STACK_SIZE)
            .spawn_scoped(scope, || {
                let mut deserializer = serde_json::Deserializer::from_slice(bytes);
                deserializer.disable_recursion_limit();
                MetricKitPayload::deserialize(&mut deserializer)
            })
            .expect("spawning MetricKit parse thread");
        match handle.join() {
            Ok(result) => result,
            // The parse thread only panics by overflowing its stack, which
            // aborts the process rather than unwinding, so this arm is
            // effectively unreachable; resume rather than invent an error.
            Err(panic) => std::panic::resume_unwind(panic),
        }
    })
}

/// Visit every frame in `roots` and their descendants, deepest-last.
///
/// Iterative: with the parse depth cap lifted, a recursive walk here would just
/// relocate the overflow. Order is not significant to any caller.
fn for_each_frame(
    roots: &[MetricKitCallStackFrame],
    mut visit: impl FnMut(&MetricKitCallStackFrame),
) {
    let mut stack: Vec<&MetricKitCallStackFrame> = roots.iter().collect();
    while let Some(frame) = stack.pop() {
        visit(frame);
        stack.extend(frame.sub_frames.iter());
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct MetricKitPayload {
    #[serde(default)]
    pub(crate) time_stamp_begin: Option<String>,
    #[serde(default)]
    pub(crate) time_stamp_end: Option<String>,
    #[serde(default)]
    pub(crate) crash_diagnostics: Vec<MetricKitCrashDiagnostic>,
    /// `MXHangDiagnostic` serializes the same `callStackTree` and
    /// `diagnosticMetaData` shape, with `hangDuration` in the metadata.
    #[serde(default)]
    pub(crate) hang_diagnostics: Vec<MetricKitCrashDiagnostic>,
}

impl MetricKitPayload {
    /// Crashes, then hangs.
    pub(crate) fn diagnostics(&self) -> impl Iterator<Item = &MetricKitCrashDiagnostic> {
        self.crash_diagnostics
            .iter()
            .chain(self.hang_diagnostics.iter())
    }

    /// Every `binaryUUID` in the payload, walked from the parsed frame tree.
    ///
    /// Kept as the reference implementation `scan_binary_uuids` is checked
    /// against; production reads UUIDs with the scan.
    #[cfg(test)]
    pub(crate) fn binary_uuids(&self) -> BTreeSet<String> {
        let mut out = BTreeSet::new();
        for crash in self.diagnostics() {
            for stack in &crash.call_stack_tree.call_stacks {
                for frame in &stack.call_stack_root_frames {
                    collect_binary_uuids(frame, &mut out);
                }
            }
        }
        out
    }

    /// Map each binary's breakpad ID to the name its frames carry, so the
    /// unresolved-UUID list can say "libxpc.dylib" instead of leaving the
    /// reader to match a bare hex string against the stacks below it.
    fn binary_names_by_breakpad_id(&self) -> BTreeMap<String, String> {
        let mut out = BTreeMap::new();
        for crash in self.diagnostics() {
            for stack in &crash.call_stack_tree.call_stacks {
                for frame in &stack.call_stack_root_frames {
                    collect_binary_names(frame, &mut out);
                }
            }
        }
        out
    }
}

fn collect_binary_names(frame: &MetricKitCallStackFrame, out: &mut BTreeMap<String, String>) {
    for_each_frame(std::slice::from_ref(frame), |frame| {
        if let (Some(uuid), Some(name)) =
            (frame.binary_uuid.as_deref(), frame.binary_name.as_deref())
            && let Some(breakpad_id) = binary_uuid_to_breakpad_id(uuid)
        {
            out.entry(breakpad_id).or_insert_with(|| name.to_string());
        }
    });
}

/// Recover the message from a caught panic payload. `panic!` payloads are
/// `&'static str` for literal messages and `String` for formatted ones; anything
/// else came from a non-standard `panic_any` and has no printable form.
fn describe_panic(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&'static str>() {
        (*message).to_string()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "unknown panic payload".to_string()
    }
}

#[cfg(test)]
fn collect_binary_uuids(frame: &MetricKitCallStackFrame, out: &mut BTreeSet<String>) {
    for_each_frame(std::slice::from_ref(frame), |frame| {
        if let Some(uuid) = frame.binary_uuid.as_deref()
            && let Ok(parsed) = Uuid::parse_str(uuid)
            && !parsed.is_nil()
        {
            out.insert(parsed.to_string().to_ascii_uppercase());
        }
    });
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct MetricKitCrashDiagnostic {
    #[serde(default)]
    version: Option<String>,
    #[serde(default)]
    pub(crate) call_stack_tree: MetricKitCallStackTree,
    #[serde(default)]
    diagnostic_meta_data: BTreeMap<String, serde_json::Value>,
    // `MXCrashDiagnostic` declares terminationReason and virtualMemoryRegionInfo
    // as properties of the diagnostic itself, but `jsonRepresentation()` folds
    // them into `diagnosticMetaData` alongside exceptionType/signal. Accept
    // either placement so the field is picked up whichever way it arrives.
    #[serde(default)]
    termination_reason: Option<String>,
    #[serde(default)]
    virtual_memory_region_info: Option<String>,
}

impl MetricKitCrashDiagnostic {
    fn termination_reason(&self) -> Option<String> {
        self.termination_reason
            .clone()
            .or_else(|| metadata_string(&self.diagnostic_meta_data, "terminationReason"))
            .filter(|reason| !reason.trim().is_empty())
    }

    fn virtual_memory_region_info(&self) -> Option<String> {
        self.virtual_memory_region_info
            .clone()
            .or_else(|| metadata_string(&self.diagnostic_meta_data, "virtualMemoryRegionInfo"))
            .filter(|info| !info.trim().is_empty())
    }
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct MetricKitCallStackTree {
    #[serde(default)]
    pub(crate) call_stacks: Vec<MetricKitCallStack>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct MetricKitCallStack {
    #[serde(default)]
    thread_attributed: bool,
    #[serde(default)]
    pub(crate) call_stack_root_frames: Vec<MetricKitCallStackFrame>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct MetricKitCallStackFrame {
    // MetricKit emits this key as `binaryUUID` (all caps), which the
    // camelCase rule would otherwise convert to `binaryUuid`.
    #[serde(default, rename = "binaryUUID")]
    pub(crate) binary_uuid: Option<String>,
    #[serde(default)]
    binary_name: Option<String>,
    #[serde(default)]
    offset_into_binary_text_segment: Option<u64>,
    #[serde(default)]
    sample_count: Option<u64>,
    #[serde(default)]
    pub(crate) sub_frames: Vec<MetricKitCallStackFrame>,
}

impl Drop for MetricKitCallStackFrame {
    /// Free the frame tree iteratively.
    ///
    /// The derived drop glue recurses once per nesting level, so letting a deep
    /// frame tree go out of scope would overflow the stack.
    ///
    /// Each frame moved into `pending` has had its children taken, so dropping
    /// it re-enters this impl with an empty vector and stops.
    fn drop(&mut self) {
        let mut pending: Vec<MetricKitCallStackFrame> = std::mem::take(&mut self.sub_frames);
        while let Some(mut frame) = pending.pop() {
            pending.extend(std::mem::take(&mut frame.sub_frames));
        }
    }
}

#[derive(Debug)]
struct SystemSymbolRequirement {
    device_type: String,
    build_id: String,
    arch: Option<String>,
    os_family: Option<String>,
}

impl MetricKitPayload {
    fn system_symbol_requirement(&self) -> Option<SystemSymbolRequirement> {
        self.diagnostics()
            .find_map(MetricKitCrashDiagnostic::system_symbol_requirement)
    }
}

impl MetricKitCrashDiagnostic {
    fn system_symbol_requirement(&self) -> Option<SystemSymbolRequirement> {
        let device_type = metadata_string(&self.diagnostic_meta_data, "deviceType")?;
        let os_version = metadata_string(&self.diagnostic_meta_data, "osVersion")?;
        let build_id = parse_os_build_id(&os_version)?;
        let arch = metadata_string(&self.diagnostic_meta_data, "platformArchitecture");
        let os_family = parse_os_family(&os_version);
        Some(SystemSymbolRequirement {
            device_type,
            build_id,
            arch,
            os_family,
        })
    }
}

/// A private temp directory for one `ipsw` invocation, removed on drop. Held
/// across every exit path of `run_ipsw_dyld_download` so a failed download
/// leaves no partly extracted IPSW behind.
struct ScratchDir(Option<PathBuf>);

impl ScratchDir {
    fn new() -> Self {
        static COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

        let seq = COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!("roam-ipsw-{}-{seq}", std::process::id()));
        match fs::create_dir_all(&path) {
            Ok(()) => Self(Some(path)),
            Err(err) => {
                tracing::warn!(?err, dir = %path.display(), "Could not create ipsw scratch dir; sharing the default TMPDIR");
                Self(None)
            }
        }
    }

    fn path(&self) -> Option<&Path> {
        self.0.as_deref()
    }
}

impl Drop for ScratchDir {
    fn drop(&mut self) {
        if let Some(path) = &self.0 {
            let _ = fs::remove_dir_all(path);
        }
    }
}

/// Per-cache download locks, keyed by `<device>/<build>/<arch>`. Entries are
/// never removed, bounded by the device/build pairs in the fleet.
fn download_gate(cache_key: &str) -> Arc<tokio::sync::Mutex<()>> {
    static GATES: OnceLock<std::sync::Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>>> =
        OnceLock::new();

    let gates = GATES.get_or_init(|| std::sync::Mutex::new(HashMap::new()));
    let mut gates = gates
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    Arc::clone(
        gates
            .entry(cache_key.to_string())
            .or_insert_with(|| Arc::new(tokio::sync::Mutex::new(()))),
    )
}

async fn extract_dyld_shared_cache(
    device_type: &str,
    build_id: &str,
    output_dir: &Path,
    arch: Option<&str>,
    os_family: Option<&str>,
) -> Result<()> {
    let mut failures: Vec<String> = Vec::new();

    // ipsw.me first on every platform: it serves Macs as well as iOS. appledb
    // picks up very new builds sooner, which makes it the better fallback.
    match run_ipsw_dyld_download(
        "ipsw.me",
        ipsw_me_args(device_type, build_id, output_dir, arch),
    )
    .await
    {
        Ok(()) => return Ok(()),
        Err(e) => failures.push(format!("ipsw.me: {e:#}")),
    }

    // The remaining sources extract from OTA zips, which `ipsw` supports only
    // on macOS. On Linux ipsw.me is the only source that can produce a cache,
    // so stop here rather than spending two minutes collecting the refusal.
    if !cfg!(target_os = "macos") {
        anyhow::bail!(
            "no dyld_shared_cache source had build {build_id} for {device_type} ({}); \
             appledb and the OTA catalog both need a macOS host to extract from an OTA",
            failures.join("; ")
        );
    }

    // appledb has a broader catalog and often carries a build before ipsw.me
    // indexes it. Requires the OS family, since `--os` is mandatory and it
    // rejects anything outside its own vocabulary.
    if let Some(os) = os_family {
        match run_ipsw_dyld_download(
            "appledb",
            appledb_args(os, device_type, build_id, output_dir, arch),
        )
        .await
        {
            Ok(()) => return Ok(()),
            Err(e) => {
                // Unauthenticated appledb gets 60 GitHub requests/hour per IP
                // and one build lookup can spend all of them, so the 403 is the
                // expected steady state rather than bad luck. Say which knob
                // fixes it, in the message that reaches the crash report.
                let hint =
                    if appledb_api_token().is_none() && format!("{e:#}").contains("rate limit") {
                        " (no IPSW_GITHUB_TOKEN set; unauthenticated appledb gets 60 GitHub \
                       requests/hour, which one build lookup can exhaust)"
                    } else {
                        ""
                    };
                failures.push(format!("appledb: {e:#}{hint}"));
            }
        }
    } else {
        failures.push("appledb: skipped (no osVersion family in payload)".to_string());
    }

    // Apple's OTA catalog last. It is the source that can serve a build the
    // other two cannot - hardware-specific Mac builds and seeds - but it is
    // also the slowest to search, so it runs only once the indexed sources have
    // both missed.
    match os_family.and_then(ota_platform) {
        Some(platform) => {
            match run_ipsw_dyld_download(
                "ota",
                ota_args(platform, device_type, build_id, output_dir, arch),
            )
            .await
            {
                Ok(()) => return Ok(()),
                Err(e) => failures.push(format!("ota: {e:#}")),
            }
        }
        None => failures.push(format!(
            "ota: skipped (no OTA platform for {})",
            os_family.unwrap_or("no osVersion family in payload")
        )),
    }

    anyhow::bail!(
        "no dyld_shared_cache source had build {build_id} for {device_type} ({})",
        failures.join("; ")
    );
}

// No `--beta` below: `ipsw` rejects it alongside `--build`, and every lookup
// here is by exact build.

/// Map a MetricKit OS family onto the vocabulary `ipsw download ota
/// --platform` accepts.
///
/// The catalog is keyed by shipping platform, so iPadOS and iPodOS live under
/// `ios`. bridgeOS has none, and None makes the caller skip the source.
fn ota_platform(os_family: &str) -> Option<&'static str> {
    match os_family {
        "iOS" | "iPadOS" | "iPodOS" => Some("ios"),
        "macOS" => Some("macos"),
        "watchOS" => Some("watchos"),
        "tvOS" => Some("tvos"),
        "audioOS" => Some("audioos"),
        _ => None,
    }
}

fn ipsw_me_args(
    device_type: &str,
    build_id: &str,
    output_dir: &Path,
    arch: Option<&str>,
) -> Vec<std::ffi::OsString> {
    let mut args: Vec<std::ffi::OsString> = vec![
        "download".into(),
        "ipsw".into(),
        "--device".into(),
        device_type.into(),
        "--build".into(),
        build_id.into(),
        "--dyld".into(),
        "--confirm".into(),
        "--output".into(),
        output_dir.as_os_str().to_owned(),
        "--no-color".into(),
    ];
    if let Some(arch) = arch {
        args.push("--dyld-arch".into());
        args.push(arch.into());
    }
    args
}

fn appledb_args(
    os_family: &str,
    device_type: &str,
    build_id: &str,
    output_dir: &Path,
    arch: Option<&str>,
) -> Vec<std::ffi::OsString> {
    // appledb doesn't expose --dyld-arch, but the --dyld extractor still
    // honors arch via the payload's arch tag in the cache filename.
    let _ = arch;
    // --api uses the GitHub API instead of a ~250 MB local clone, which often
    // hangs the first run on stateless containers.
    //
    // --type ota is required: `--dyld` only extracts from OTA zips, and --type
    // defaults to `ipsw`. See also the macOS gate in
    // `extract_dyld_shared_cache`.
    let mut args: Vec<std::ffi::OsString> = vec![
        "download".into(),
        "appledb".into(),
        "--api".into(),
        "--type".into(),
        "ota".into(),
        "--os".into(),
        os_family.into(),
        "--device".into(),
        device_type.into(),
        "--build".into(),
        build_id.into(),
        "--dyld".into(),
        "--confirm".into(),
        "--output".into(),
        output_dir.as_os_str().to_owned(),
        "--no-color".into(),
    ];

    // Unauthenticated GitHub calls get 60 requests/hour per IP, and one build
    // lookup can spend all of them. A token raises the limit to 5000/hour.
    if let Some(token) = appledb_api_token() {
        args.push("--api-token".into());
        args.push(token.into());
    }

    args
}

/// Args for Apple's own OTA catalog.
///
/// The only source needing no third-party index. Carries hardware-specific
/// builds and seeds that never reach ipsw.me, and exposes `--dyld-arch`.
fn ota_args(
    platform: &str,
    device_type: &str,
    build_id: &str,
    output_dir: &Path,
    arch: Option<&str>,
) -> Vec<std::ffi::OsString> {
    let mut args: Vec<std::ffi::OsString> = vec![
        "download".into(),
        "ota".into(),
        "--platform".into(),
        platform.into(),
        "--device".into(),
        device_type.into(),
        "--build".into(),
        build_id.into(),
        "--dyld".into(),
        "--confirm".into(),
        "--output".into(),
        output_dir.as_os_str().to_owned(),
        "--no-color".into(),
    ];
    if let Some(arch) = arch {
        args.push("--dyld-arch".into());
        args.push(arch.into());
    }
    args
}

/// GitHub token for appledb's API lookups, if configured.
///
/// Read from the environment so the worker can set it alongside the other
/// `ipsw` credentials. `GITHUB_TOKEN` is accepted as a fallback.
fn appledb_api_token() -> Option<String> {
    ["IPSW_GITHUB_TOKEN", "GITHUB_TOKEN"]
        .iter()
        .find_map(|key| std::env::var(key).ok())
        .map(|token| token.trim().to_string())
        .filter(|token| !token.is_empty())
}

/// Upper bound for any single ipsw download attempt. Real macOS dyld
/// caches embedded in IPSWs are several GB, so this is generous,
/// but bounded so a hung subprocess can't pin the worker forever.
const IPSW_DOWNLOAD_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(8 * 60 * 60);

async fn run_ipsw_dyld_download(label: &str, args: Vec<std::ffi::OsString>) -> Result<()> {
    use portable_pty::{CommandBuilder, PtySize, native_pty_system};
    use std::io::Read;

    // Cap concurrent downloads. Several `ipsw` processes over one link each
    // get a fraction of the bandwidth and all finish late. This gate is about
    // throughput; `download_gate` is about correctness.
    static DOWNLOAD_SLOTS: OnceLock<tokio::sync::Semaphore> = OnceLock::new();
    let _slot = DOWNLOAD_SLOTS
        .get_or_init(|| tokio::sync::Semaphore::new(2))
        .acquire()
        .await
        .expect("download semaphore is never closed");

    tracing::info!(strategy = label, "Trying ipsw dyld download");
    let started = std::time::Instant::now();

    // Redact the value following --api-token: these args are logged verbatim to
    // the journal, and the GitHub token would otherwise sit there in plaintext.
    let mut redact_next = false;
    let logged_args: Vec<String> = args
        .iter()
        .map(|arg| {
            let arg = arg.to_string_lossy();
            let rendered = if redact_next {
                "<redacted>".to_string()
            } else {
                arg.to_string()
            };
            redact_next = arg == "--api-token";
            rendered
        })
        .collect();
    tracing::info!("Running ipsw with args: {:?}", logged_args);

    // ipsw's progress bar checks `isatty` and renders nothing off a terminal,
    // so allocate a pty and read its master end like any other pipe.
    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(PtySize {
            rows: 40,
            cols: 120,
            pixel_width: 0,
            pixel_height: 0,
        })
        .with_context(|| format!("opening pty for `ipsw download {label} --dyld`"))?;

    let mut cmd = CommandBuilder::new("ipsw");
    for arg in &args {
        cmd.arg(arg);
    }
    if let Ok(cwd) = std::env::current_dir() {
        cmd.cwd(cwd);
    }
    // mpb consults TERM as a sanity check before drawing; give it something
    // unambiguously real so it doesn't fall back to the no-tty path.
    cmd.env("TERM", "xterm-256color");

    // Give this run its own TMPDIR. `ipsw` mounts the DMG at a path derived
    // from the DMG name, so two runs on identically named DMGs collide and
    // report `fusermount3: Permission denied`. `download_gate` covers the
    // same-cache case; this covers the cross-cache one. Best-effort.
    let scratch = ScratchDir::new();
    if let Some(path) = scratch.path() {
        cmd.env("TMPDIR", path);
    }

    let mut child = pair.slave.spawn_command(cmd).with_context(|| {
        format!(
            "spawning `ipsw download {label} --dyld`; install https://github.com/blacktop/ipsw to enable automatic system-symbol extraction"
        )
    })?;

    // Drop our copy of the slave so the master sees EOF once the child closes
    // its end. Without this the read loop hangs forever after ipsw exits.
    drop(pair.slave);

    let mut reader = pair
        .master
        .try_clone_reader()
        .with_context(|| "cloning pty master reader")?;
    // Hold the master alive until reads complete; dropping it early can race
    // the read task to EIO before the final bytes drain.
    let _master = pair.master;

    let mut killer = child.clone_killer();

    let (tx, rx) = tokio::sync::mpsc::channel::<Vec<u8>>(64);
    let read_handle = tokio::task::spawn_blocking(move || {
        let mut buf = [0u8; 4096];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    if tx.blocking_send(buf[..n].to_vec()).is_err() {
                        break;
                    }
                }
                // Linux returns EIO on a master pty after the slave fully
                // closes; treat any error as end-of-stream.
                Err(_) => break,
            }
        }
    });

    let proc_handle = tokio::spawn(process_ipsw_stream(rx, label.to_string()));
    let wait_handle = tokio::task::spawn_blocking(move || child.wait());

    let status = match tokio::time::timeout(IPSW_DOWNLOAD_TIMEOUT, wait_handle).await {
        Ok(join_res) => join_res
            .with_context(|| "ipsw wait task panicked")?
            .with_context(|| format!("waiting on `ipsw download {label} --dyld` to finish"))?,
        Err(_) => {
            let _ = killer.kill();
            let elapsed_ms = started.elapsed().as_millis() as u64;
            tracing::warn!(
                strategy = label,
                elapsed_ms,
                timeout_secs = IPSW_DOWNLOAD_TIMEOUT.as_secs(),
                "ipsw dyld download timed out; killed"
            );
            anyhow::bail!("timed out after {}s", IPSW_DOWNLOAD_TIMEOUT.as_secs());
        }
    };

    let _ = read_handle.await;
    let captured = proc_handle.await.unwrap_or_default();

    let elapsed_ms = started.elapsed().as_millis() as u64;
    if !status.success() {
        let summary = extract_ipsw_error_message(&captured, &captured);
        tracing::info!(
            strategy = label,
            elapsed_ms,
            exit_code = status.exit_code(),
            error = %summary,
            "ipsw dyld download did not succeed"
        );
        anyhow::bail!("exit {}: {}", status.exit_code(), summary);
    }
    tracing::info!(strategy = label, elapsed_ms, "ipsw dyld download succeeded");
    Ok(())
}

/// Consumes raw pty bytes from the reader task, splitting on `\r` and `\n`
/// (ipsw redraws its progress bar with `\r`), and emits records via tracing.
///
/// Two modes:
/// - non-progress lines (`Parsing remote IPSW`, errors, etc.) are logged immediately;
/// - the most recent progress line is logged at most every 15s.
///
/// Returns the full captured byte stream so the caller can pass it to
/// `extract_ipsw_error_message` on failure.
async fn process_ipsw_stream(
    mut rx: tokio::sync::mpsc::Receiver<Vec<u8>>,
    label: String,
) -> String {
    const PROGRESS_LOG_INTERVAL: std::time::Duration = std::time::Duration::from_secs(15);

    let mut full: Vec<u8> = Vec::new();
    let mut current: Vec<u8> = Vec::new();
    let mut latest_progress: Option<String> = None;

    // Delay the first tick so we don't fire before any progress has arrived.
    let mut interval = tokio::time::interval_at(
        tokio::time::Instant::now() + PROGRESS_LOG_INTERVAL,
        PROGRESS_LOG_INTERVAL,
    );

    loop {
        tokio::select! {
            chunk = rx.recv() => {
                let Some(chunk) = chunk else { break; };
                full.extend_from_slice(&chunk);
                for &byte in &chunk {
                    match byte {
                        b'\r' | b'\n' => {
                            consume_ipsw_line(&current, &label, &mut latest_progress);
                            current.clear();
                        }
                        _ => current.push(byte),
                    }
                }
            }
            _ = interval.tick() => {
                if let Some(progress) = latest_progress.as_deref() {
                    tracing::info!(strategy = %label, "ipsw progress: {progress}");
                }
            }
        }
    }

    if !current.is_empty() {
        consume_ipsw_line(&current, &label, &mut latest_progress);
    }
    if let Some(progress) = latest_progress {
        tracing::info!(strategy = %label, "ipsw progress: {progress}");
    }
    String::from_utf8_lossy(&full).into_owned()
}

fn consume_ipsw_line(bytes: &[u8], label: &str, latest_progress: &mut Option<String>) {
    let line = String::from_utf8_lossy(bytes);
    // mpb leaves cursor-movement codes in the stream even with --no-color; strip
    // them so the rendered progress text is readable in tracing.
    let cleaned = strip_ansi_csi(&line);
    let trimmed = cleaned.trim();
    if trimmed.is_empty() {
        return;
    }
    if looks_like_ipsw_progress(trimmed) {
        *latest_progress = Some(trimmed.to_string());
    } else {
        tracing::info!(strategy = label, "ipsw: {trimmed}");
    }
}

fn looks_like_ipsw_progress(line: &str) -> bool {
    // Progress bar shape: "<size> / <size> [<bar>| <eta> ] <rate>".
    line.contains(" / ") && line.contains('[') && line.contains(']')
}

/// Strips ANSI CSI escape sequences (`\x1b[...<final>`) from `s`. Doesn't try to
/// handle other escape forms (OSC, charset selection, etc.) - mpb only emits CSI.
fn strip_ansi_csi(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\x1b' && chars.peek() == Some(&'[') {
            chars.next();
            for next in chars.by_ref() {
                if matches!(next as u32, 0x40..=0x7e) {
                    break;
                }
            }
        } else {
            out.push(c);
        }
    }
    out
}

/// `ipsw` dumps full --help output to stdout on cobra-level argument or
/// lookup failures. Pull just the lines that look like real diagnostics so
/// we don't flood the log with the help text.
fn extract_ipsw_error_message(stderr: &str, stdout: &str) -> String {
    let mut interesting = stderr
        .lines()
        .chain(stdout.lines())
        .map(str::trim)
        .filter(|line| {
            !line.is_empty()
                && (line.starts_with('⨯')
                    || line.contains("Error:")
                    || line.contains("error:")
                    || line.contains("not found")
                    || line.contains("did not match"))
        })
        .collect::<Vec<_>>();
    interesting.dedup();
    if interesting.is_empty() {
        "(no error output from ipsw)".to_string()
    } else {
        interesting.join(" | ")
    }
}

/// On-disk budget for downloaded system dyld shared caches.
///
/// Each cache is 5-6 GB, one per `<device>/<build>` pair: Apple builds the
/// shared cache per device family, so two models on the same build have
/// different files. The directory grows as the fleet spreads.
const DEFAULT_SYSTEM_CACHE_MAX_BYTES: u64 = 256 * 1024 * 1024 * 1024;

/// Covers `system/` only. `uploads/` holds our own dSYMs, which are far
/// smaller and are not re-downloadable, so they are never evicted.
fn system_cache_budget() -> u64 {
    std::env::var("SYMBOLICATE_CACHE_MAX_BYTES")
        .ok()
        .and_then(|raw| raw.trim().parse::<u64>().ok())
        .filter(|bytes| *bytes > 0)
        .unwrap_or(DEFAULT_SYSTEM_CACHE_MAX_BYTES)
}

/// Marker file whose mtime records when a cached dyld cache was last used.
///
/// Recorded explicitly rather than read from atime, which `relatime` and
/// `noatime` make coarse or absent.
const LAST_USED_MARKER: &str = ".last-used";

/// Record that `cache_entry_dir` was used just now. Best-effort: a cache that
/// cannot be marked simply looks older than it is, which costs a re-download
/// rather than correctness.
fn touch_last_used(cache_entry_dir: &Path) {
    let marker = cache_entry_dir.join(LAST_USED_MARKER);
    if let Err(err) = fs::write(&marker, b"") {
        tracing::debug!(?err, path = %marker.display(), "Could not update cache last-used marker");
    }
}

/// When `cache_entry_dir` was last used, falling back to the directory's own
/// mtime for entries downloaded before markers existed.
fn last_used_at(cache_entry_dir: &Path) -> std::time::SystemTime {
    let marker = cache_entry_dir.join(LAST_USED_MARKER);
    fs::metadata(&marker)
        .or_else(|_| fs::metadata(cache_entry_dir))
        .and_then(|meta| meta.modified())
        .unwrap_or(std::time::UNIX_EPOCH)
}

/// Recursive on-disk size of a directory, counting allocated blocks rather than
/// apparent length so the number matches what `df` reports.
fn dir_size_bytes(dir: &Path) -> u64 {
    let mut total = 0;
    let mut stack = vec![dir.to_path_buf()];
    while let Some(path) = stack.pop() {
        let Ok(entries) = fs::read_dir(&path) else {
            continue;
        };
        for entry in entries.flatten() {
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            if file_type.is_dir() {
                stack.push(entry.path());
            } else if let Ok(meta) = entry.metadata() {
                #[cfg(unix)]
                {
                    use std::os::unix::fs::MetadataExt as _;
                    total += meta.blocks() * 512;
                }
                #[cfg(not(unix))]
                {
                    total += meta.len();
                }
            }
        }
    }
    total
}

/// Drop least-recently-used `<device>/<build>` caches until the tree fits in
/// `max_bytes`.
///
/// Whole entries are evicted, not individual files: a half-deleted entry would
/// still satisfy `dyld_cache_exists` and then fail to symbolicate. `keep` is
/// the entry the caller is about to use.
///
/// Best-effort: failing to reclaim space must not fail the symbolication.
async fn enforce_system_cache_budget(system_root: &Path, keep: &Path, max_bytes: u64) {
    let system_root = system_root.to_path_buf();
    let keep = keep.to_path_buf();

    // Sizing walks tens of thousands of directory entries; keep it off the
    // async worker threads.
    let result = tokio::task::spawn_blocking(move || {
        let mut entries: Vec<(PathBuf, u64, std::time::SystemTime)> = Vec::new();

        let Ok(devices) = fs::read_dir(&system_root) else {
            return None;
        };
        for device in devices.flatten() {
            if !device.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                continue;
            }
            let Ok(builds) = fs::read_dir(device.path()) else {
                continue;
            };
            for build in builds.flatten() {
                if !build.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                    continue;
                }
                let path = build.path();
                let size = dir_size_bytes(&path);
                let used = last_used_at(&path);
                entries.push((path, size, used));
            }
        }

        let total: u64 = entries.iter().map(|(_, size, _)| size).sum();
        if total <= max_bytes {
            return Some((total, total, 0usize));
        }

        // Least-recently-used first.
        entries.sort_by_key(|(_, _, used)| *used);

        let mut remaining = total;
        let mut evicted = 0usize;
        for (path, size, _) in entries {
            if remaining <= max_bytes {
                break;
            }
            if path == keep {
                continue;
            }
            match fs::remove_dir_all(&path) {
                Ok(()) => {
                    tracing::info!(
                        path = %path.display(),
                        freed_bytes = size,
                        "Evicted least-recently-used system dyld cache"
                    );
                    remaining = remaining.saturating_sub(size);
                    evicted += 1;
                }
                Err(err) => {
                    tracing::warn!(?err, path = %path.display(), "Could not evict system dyld cache");
                }
            }
        }
        Some((total, remaining, evicted))
    })
    .await;

    match result {
        Ok(Some((before, after, evicted))) if evicted > 0 => {
            tracing::info!(
                bytes_before = before,
                bytes_after = after,
                max_bytes,
                evicted_entries = evicted,
                "Enforced system dyld cache budget"
            );
        }
        Ok(Some((before, _, _))) => {
            tracing::debug!(
                bytes = before,
                max_bytes,
                "System dyld cache within budget; nothing evicted"
            );
        }
        Ok(None) => {}
        Err(err) => {
            tracing::warn!(?err, "System dyld cache eviction task failed");
        }
    }
}

/// Files Apple ships alongside the split cache, and `ipsw` copies out last.
///
/// Their presence separates a finished download from a truncated one: a cache
/// cut off mid-copy still has a base file and subcaches, so it would read as
/// cached forever. Every intact cache carries `.atlas`; iOS adds `.symbols`
/// and macOS adds `.map`, so any of the three will do.
const DYLD_CACHE_TRAILER_SUFFIXES: [&str; 3] = [".atlas", ".symbols", ".map"];

async fn dyld_cache_exists(dyld_dir: &Path, arch: Option<&str>) -> Result<bool> {
    normalize_dyld_dir(dyld_dir);

    let Ok(mut entries) = tokio::fs::read_dir(dyld_dir).await else {
        return Ok(false);
    };

    let mut has_cache_for_arch = false;
    let mut has_trailer = false;

    while let Some(entry) = entries.next_entry().await? {
        let filename = entry.file_name().to_string_lossy().to_string();
        if !filename.starts_with("dyld_shared_cache") {
            continue;
        }
        if !arch.is_none_or(|arch| filename.contains(arch)) {
            continue;
        }
        if DYLD_CACHE_TRAILER_SUFFIXES
            .iter()
            .any(|suffix| filename.ends_with(suffix))
        {
            has_trailer = true;
        } else {
            has_cache_for_arch = true;
        }
    }

    Ok(has_cache_for_arch && has_trailer)
}

/// `ipsw download ipsw --dyld --output X` extracts the dyld_shared_cache
/// files into a nested `X/<build>__<device>/` subdirectory, but the rest of
/// the symbolicator (existence check + samply lookup) expects the caches
/// to live directly under `X/`. Flatten any such subdirectory in-place.
/// Idempotent.
fn normalize_dyld_dir(dyld_dir: &Path) {
    let Ok(entries) = fs::read_dir(dyld_dir) else {
        return;
    };

    let subdirs: Vec<PathBuf> = entries
        .flatten()
        .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
        .map(|e| e.path())
        .collect();

    for subdir in subdirs {
        let Ok(inner) = fs::read_dir(&subdir) else {
            continue;
        };
        let inner_entries: Vec<fs::DirEntry> = inner.flatten().collect();

        let has_cache_files = inner_entries.iter().any(|e| {
            e.file_name()
                .to_string_lossy()
                .starts_with("dyld_shared_cache")
        });
        if !has_cache_files {
            continue;
        }

        for inner_entry in inner_entries {
            let from = inner_entry.path();
            let to = dyld_dir.join(inner_entry.file_name());
            if to.exists() {
                continue;
            }
            if let Err(error) = fs::rename(&from, &to) {
                tracing::warn!(
                    ?error,
                    from = %from.display(),
                    to = %to.display(),
                    "failed to flatten dyld cache; leaving nested layout in place"
                );
                return;
            }
        }
        let _ = fs::remove_dir(&subdir);
    }
}

fn metadata_string(metadata: &BTreeMap<String, serde_json::Value>, key: &str) -> Option<String> {
    metadata
        .get(key)
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
}

/// Read a metadata value that MetricKit may encode either as a JSON number or
/// as a string (`"signal": 9` vs `"signal": "9"` both occur in the wild).
fn metadata_u64(metadata: &BTreeMap<String, serde_json::Value>, key: &str) -> Option<u64> {
    let value = metadata.get(key)?;
    value
        .as_u64()
        .or_else(|| value.as_str().and_then(|text| text.trim().parse().ok()))
}

/// Mach exception type names, from `<mach/exception_types.h>`.
fn exception_type_name(exception_type: u64) -> Option<&'static str> {
    Some(match exception_type {
        1 => "EXC_BAD_ACCESS",
        2 => "EXC_BAD_INSTRUCTION",
        3 => "EXC_ARITHMETIC",
        4 => "EXC_EMULATION",
        5 => "EXC_SOFTWARE",
        6 => "EXC_BREAKPOINT",
        7 => "EXC_SYSCALL",
        8 => "EXC_MACH_SYSCALL",
        9 => "EXC_RPC_ALERT",
        10 => "EXC_CRASH",
        11 => "EXC_RESOURCE",
        12 => "EXC_GUARD",
        13 => "EXC_CORPSE_NOTIFY",
        _ => return None,
    })
}

/// `kern_return_t` values that show up as `exceptionCode` under
/// EXC_BAD_ACCESS, from `<mach/kern_return.h>`. Other exception types encode
/// entirely different things in the same field, so only decode the one.
fn bad_access_code_name(exception_type: u64, code: u64) -> Option<&'static str> {
    if exception_type != 1 {
        return None;
    }
    Some(match code {
        1 => "KERN_INVALID_ADDRESS",
        2 => "KERN_PROTECTION_FAILURE",
        _ => return None,
    })
}

/// True when the faulting address sits in a guard region below a thread stack,
/// which is the signature of a stack overflow.
///
/// `virtualMemoryRegionInfo` is a small VM map with the region containing the
/// faulting address marked by a leading `--->`:
///
/// ```text
/// 0x16eddbda0 is in 0x16b5d8000-0x16eddc000;  bytes after start: 58736032  bytes before end: 607
///       REGION TYPE                    START - END         [ VSIZE] PRT/MAX SHRMOD  REGION DETAIL
///       MALLOC metadata             13a600000-13a604000    [   16K] rw-/rwx SM=PRV
///       GAP OF 0x30fd4000 BYTES
/// --->  Stack Guard                 16b5d8000-16eddc000    [ 56.0M] ---/rwx SM=PRV
///       Stack                       16eddc000-16f5d8000    [ 8176K] rw-/rwx SM=SHM
/// ```
fn faulting_address_is_in_stack_guard(region_info: &str) -> bool {
    region_info.lines().any(|line| {
        let line = line.trim_start();
        line.starts_with("--->") && line.to_ascii_lowercase().contains("stack guard")
    })
}

/// Collapse a samply candidate-path error into one readable line.
///
/// `SymbolManager` reports every path it tried: each cache on disk crossed
/// with each plausible install path. One missing cache produces hundreds of
/// near-identical lines.
fn summarize_lookup_error(error: &str) -> String {
    let mut absent_paths = 0usize;
    let mut build_mismatches = 0usize;
    let mut other: Vec<String> = Vec::new();

    for line in error.lines().map(str::trim).filter(|line| !line.is_empty()) {
        if line.starts_with("All candidate paths encountered failures") {
            continue;
        }
        if line.contains("dyld shared cache file did not include an entry") {
            absent_paths += 1;
        } else if line.starts_with("Unmatched breakpad_id") {
            build_mismatches += 1;
        } else if !other.iter().any(|seen| seen == line) {
            other.push(line.to_string());
        }
    }

    let mut parts: Vec<String> = Vec::new();
    if build_mismatches > 0 {
        // Some cache on disk *did* hold this dylib, just built from a different
        // OS - so it is a system library and the fix is fetching the right
        // dyld shared cache.
        parts.push(format!(
            "{build_mismatches} cached dyld shared cache(s) had this dylib but from a different \
             OS build - the cache for this crash's OS build was never downloaded"
        ));
        if absent_paths > 0 {
            parts.push(format!(
                "{absent_paths} candidate path(s) not present in any cached dyld shared cache"
            ));
        }
    } else if absent_paths > 0 {
        // No cache held anything at these paths and no dSYM was on file.
        // Usually one of our own binaries with no dSYM uploaded, but not
        // always, so do not claim that outright. Paths are resolved through
        // each cache's `.map`, so a system library here means the cache for
        // this OS build is absent.
        parts.push(format!(
            "no dSYM on file, and none of the {absent_paths} candidate path(s) exists in any \
             cached dyld shared cache. If this is one of our binaries, upload the dSYM for this \
             build; if it is a system library, the shared cache for this OS build was never \
             downloaded"
        ));
    }
    // Anything we don't recognise is likely the interesting part (a missing
    // dSYM, a parse failure, a panic), so keep it rather than counting it.
    parts.extend(other.into_iter().take(4));

    if parts.is_empty() {
        return error.split_whitespace().collect::<Vec<_>>().join(" ");
    }
    parts.join("; ")
}

/// Unix signal names, from `<sys/signal.h>`.
fn signal_name(signal: u64) -> Option<&'static str> {
    Some(match signal {
        1 => "SIGHUP",
        2 => "SIGINT",
        3 => "SIGQUIT",
        4 => "SIGILL",
        5 => "SIGTRAP",
        6 => "SIGABRT",
        7 => "SIGEMT",
        8 => "SIGFPE",
        9 => "SIGKILL",
        10 => "SIGBUS",
        11 => "SIGSEGV",
        12 => "SIGSYS",
        13 => "SIGPIPE",
        14 => "SIGALRM",
        15 => "SIGTERM",
        _ => return None,
    })
}

/// Plain-English meaning of the well-known OS termination codes that show up in
/// `MXCrashDiagnostic.terminationReason`.
fn termination_code_explanation(code: u64) -> Option<&'static str> {
    Some(match code {
        0xdead10cc => {
            "held a file lock or SQLite/WAL lock on a file in a shared app-group \
             container while being suspended"
        }
        0x8badf00d => "watchdog timeout - took too long to launch, resume, suspend, or terminate",
        0xbaadca11 => "failed to report a PushKit VoIP call after waking for one",
        0xc00010ff => "terminated because the device got too hot",
        0xdeadfa11 => "force-quit by the user",
        0x2bad45ec => "terminated for a security violation",
        0xbad22222 => "VoIP app was resuming too frequently",
        0xc51bad01 => "background task ran out of its CPU time budget",
        0xc51bad02 => "background task ran out of its wall-clock time budget",
        0xc51bad03 => "background task was not given enough CPU time to finish",
        _ => return None,
    })
}

/// Pull the `Code 0x...` value out of a termination reason string such as
/// `"Namespace SPRINGBOARD, Code 0xdead10cc"`.
fn parse_termination_code(termination_reason: &str) -> Option<u64> {
    let start = termination_reason.find("0x")? + 2;
    let digits: String = termination_reason[start..]
        .chars()
        .take_while(char::is_ascii_hexdigit)
        .collect();
    if digits.is_empty() {
        return None;
    }
    u64::from_str_radix(&digits, 16).ok()
}

/// One-line interpretation of why the process died, assembled from
/// `exceptionType` / `signal` / `terminationReason`.
///
/// `terminationReason` is what distinguishes an OS policy kill (`EXC_CRASH` +
/// `SIGKILL`) from a real fault, so name it when present and say so when not.
fn describe_termination(
    metadata: &BTreeMap<String, serde_json::Value>,
    termination_reason: Option<&str>,
    region_info: Option<&str>,
) -> Option<String> {
    let exception_type = metadata_u64(metadata, "exceptionType");
    let signal = metadata_u64(metadata, "signal");

    let mut parts: Vec<String> = Vec::new();

    if let Some(exception_type) = exception_type {
        let mut part = match exception_type_name(exception_type) {
            Some(name) => format!("{name} ({exception_type})"),
            None => format!("exception type {exception_type}"),
        };
        // exceptionCode is a `kern_return_t` read against the exception type.
        // For EXC_BAD_ACCESS it says whether the address was unmapped or just
        // unwritable.
        if let Some(code) = metadata_u64(metadata, "exceptionCode") {
            match bad_access_code_name(exception_type, code) {
                Some(name) => part.push_str(&format!(" / {name} ({code})")),
                None => part.push_str(&format!(" / code {code}")),
            }
        }
        parts.push(part);
    }

    if let Some(signal) = signal {
        parts.push(match signal_name(signal) {
            Some(name) => format!("{name} ({signal})"),
            None => format!("signal {signal}"),
        });
    }

    if parts.is_empty() && termination_reason.is_none() {
        return None;
    }

    let mut description = parts.join(" / ");

    // A fault in the guard region below a stack is an overflow, not a wild
    // pointer. Worth naming: the backtrace is routinely empty for these.
    if region_info.is_some_and(faulting_address_is_in_stack_guard) {
        if !description.is_empty() {
            description.push_str(" - ");
        }
        description.push_str(
            "stack overflow: the faulting address is inside the Stack Guard region directly \
             below a thread stack, so the thread ran off the end of its stack. Look for \
             unbounded recursion or a very large stack allocation, not a dangling pointer.",
        );
    }

    match termination_reason.and_then(parse_termination_code) {
        Some(code) => {
            let explanation = termination_code_explanation(code)
                .unwrap_or("see the termination reason above for the owning subsystem");
            if !description.is_empty() {
                description.push_str(" - ");
            }
            description.push_str(&format!("0x{code:x}: {explanation}"));
        }
        None => {
            // EXC_CRASH with SIGKILL is an OS kill, not an app fault. Without
            // a terminationReason, name the candidate policies.
            if exception_type == Some(10) && signal == Some(9) {
                description.push_str(
                    " - killed by the OS, not an in-process fault. No terminationReason in \
                     the payload, so the specific policy is unconfirmed; the usual candidates \
                     are 0xdead10cc (suspended while holding a file/SQLite lock in a shared \
                     container), 0x8badf00d (watchdog), and 0xc51bad0* (background task budget).",
                );
            }

            // EXC_BREAKPOINT / SIGTRAP in a shipped build is the Swift runtime
            // trapping. The innermost frame is libswiftCore, so the useful one
            // is the first below it in the app's binary.
            if exception_type == Some(6) || signal == Some(5) {
                if !description.is_empty() {
                    description.push_str(" - ");
                }
                description.push_str(
                    "a deliberate Swift runtime trap, not a memory fault: force-unwrapping a \
                     nil Optional, indexing out of range, arithmetic overflow, a failed \
                     precondition/assert, or an explicit fatalError. Read the first frame \
                     below libswiftCore that belongs to the app - that is the call that \
                     trapped.",
                );
            }
        }
    }

    Some(description)
}

fn parse_os_build_id(os_version: &str) -> Option<String> {
    let start = os_version.rfind('(')? + 1;
    let end = os_version[start..].find(')')? + start;
    Some(os_version[start..end].to_string())
}

/// Canonicalize MetricKit's `osVersion` into the vocabulary `ipsw download
/// appledb --os` accepts.
///
/// MetricKit names the OS as Apple does in release notes ("iPhone OS 26.6
/// (23G71)"), so the first token is "iPhone", which appledb rejects.
///
/// Unrecognized families return None so the caller skips appledb. The list is
/// appledb's, not Apple's: visionOS is absent because appledb rejects it.
fn parse_os_family(os_version: &str) -> Option<String> {
    // Longest-first, so "iPhone OS" is matched before any shorter prefix and
    // "iPadOS" is never mistaken for "iOS".
    const FAMILIES: &[(&str, &str)] = &[
        ("iPhone OS", "iOS"),
        ("Mac OS X", "macOS"),
        ("bridgeOS", "bridgeOS"),
        ("watchOS", "watchOS"),
        ("audioOS", "audioOS"),
        ("iPadOS", "iPadOS"),
        ("iPodOS", "iPodOS"),
        ("macOS", "macOS"),
        ("tvOS", "tvOS"),
        ("iOS", "iOS"),
    ];

    let trimmed = os_version.trim();
    FAMILIES
        .iter()
        .find(|(prefix, _)| {
            trimmed
                .get(..prefix.len())
                .is_some_and(|head| head.eq_ignore_ascii_case(prefix))
        })
        .map(|(_, canonical)| (*canonical).to_string())
}

/// Install paths inside one dyld shared cache, keyed by final path component.
type DyldMapIndex = HashMap<String, Vec<String>>;

/// Parsed `.map` sidecars, keyed by the cache they belong to. `None` records a
/// cache whose map is missing or unreadable, so a bad sidecar is parsed once
/// rather than on every lookup.
static DYLD_MAP_INDEXES: OnceLock<Mutex<HashMap<PathBuf, Option<Arc<DyldMapIndex>>>>> =
    OnceLock::new();

/// The paths to try inside one shared cache for one library.
///
/// Guessed install paths cannot reach a framework nested inside another, such
/// as `AE` under `CoreServices.framework` or `HIToolbox` under `Carbon`. Each
/// cache ships a `.map` sidecar listing real install paths, so look the name up
/// there first and fall back to the guesses when the sidecar is missing.
fn resolve_dylib_paths_in_cache(
    cache_path: &Path,
    leaf_name: Option<&str>,
    guessed: &[String],
) -> Vec<String> {
    let mut paths: Vec<String> = Vec::new();

    if let Some(name) = leaf_name
        && let Some(index) = dyld_map_index(cache_path)
        && let Some(found) = index.get(name)
    {
        paths.extend(found.iter().cloned());
    }

    for path in guessed {
        if !paths.contains(path) {
            paths.push(path.clone());
        }
    }

    paths
}

/// The parsed `.map` sidecar for one shared cache, read at most once.
fn dyld_map_index(cache_path: &Path) -> Option<Arc<DyldMapIndex>> {
    let indexes = DYLD_MAP_INDEXES.get_or_init(|| Mutex::new(HashMap::new()));
    // A poisoned lock means another thread panicked mid-parse. The map is a
    // pure cache, so recovering the guard is safe and better than poisoning
    // symbolication for the rest of the process.
    let mut indexes = indexes
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(cached) = indexes.get(cache_path) {
        return cached.clone();
    }

    let map_path = dyld_map_path(cache_path);
    let parsed = match parse_dyld_map(&map_path) {
        Ok(index) => Some(Arc::new(index)),
        Err(error) => {
            // Not every cache ships one -- the local Cryptexes path has no
            // sidecar -- so this is expected, not a failure.
            tracing::debug!(?map_path, %error, "No dyld shared cache .map sidecar");
            None
        }
    };
    indexes.insert(cache_path.to_path_buf(), parsed.clone());
    parsed
}

/// `dyld_shared_cache_arm64e` -> `dyld_shared_cache_arm64e.map`.
///
/// Appended rather than set with `with_extension`, which would truncate at a dot
/// in the arch suffix.
fn dyld_map_path(cache_path: &Path) -> PathBuf {
    match cache_path.file_name() {
        Some(name) => {
            let mut name = name.to_os_string();
            name.push(".map");
            cache_path.with_file_name(name)
        }
        None => cache_path.to_path_buf(),
    }
}

/// Install paths in a `.map` sidecar, keyed by final path component.
///
/// The format is a mapping table, then one flush-left absolute install path per
/// dylib, each followed by indented segment lines. Only the flush-left lines are
/// paths.
fn parse_dyld_map(map_path: &Path) -> std::io::Result<DyldMapIndex> {
    let reader = BufReader::new(File::open(map_path)?);
    let mut index: DyldMapIndex = HashMap::new();

    for line in reader.lines() {
        let line = line?;
        if !line.starts_with('/') {
            continue;
        }
        let Some(leaf) = line.rsplit('/').next().filter(|leaf| !leaf.is_empty()) else {
            continue;
        };
        index
            .entry(leaf.to_string())
            .or_default()
            .push(line.clone());
    }

    Ok(index)
}

fn likely_dylib_paths(library_info: &LibraryInfo) -> Vec<String> {
    let mut paths = BTreeSet::new();
    if let Some(path) = &library_info.path {
        paths.insert(path.clone());
    }

    let Some(name) = library_info
        .name
        .as_deref()
        .or(library_info.debug_name.as_deref())
    else {
        return paths.into_iter().collect();
    };

    if name.ends_with(".dylib") {
        paths.insert(format!("/usr/lib/{name}"));
        paths.insert(format!("/usr/lib/system/{name}"));
        // Swift runtime dylibs (libswiftCore, libswift_Concurrency, ...)
        // live under /usr/lib/swift/ in the dyld shared cache.
        paths.insert(format!("/usr/lib/swift/{name}"));
    } else {
        // macOS framework install_names are versioned (Versions/A/<Name>,
        // sometimes Versions/C/<Name> for AppKit/Foundation). iOS-style
        // caches use the bare path. Try both layouts.
        for parent in ["Frameworks", "PrivateFrameworks"] {
            paths.insert(format!("/System/Library/{parent}/{name}.framework/{name}"));
            for ver in ["A", "B", "C"] {
                paths.insert(format!(
                    "/System/Library/{parent}/{name}.framework/Versions/{ver}/{name}"
                ));
            }
        }
        paths.insert(format!("/usr/lib/{name}.dylib"));
        paths.insert(format!("/usr/lib/system/{name}.dylib"));
        // dyld is neither a framework nor a .dylib; its install_name is /usr/lib/dyld.
        if name == "dyld" {
            paths.insert("/usr/lib/dyld".to_string());
        }
    }

    paths.into_iter().collect()
}

fn binary_uuid_to_breakpad_id(binary_uuid: &str) -> Option<String> {
    let uuid = Uuid::parse_str(binary_uuid).ok()?;
    if uuid.is_nil() {
        return None;
    }
    Some(DebugId::from_uuid(uuid).breakpad().to_string())
}

fn render_metric_report(
    diagnostics: &RoamDebugInfo,
    installation_info: &DeviceInfo,
    payload: &MetricKitPayload,
    symbolicated_addresses: &BTreeMap<String, LookedUpAddresses>,
    lookup_errors: &BTreeMap<String, String>,
) -> Result<String> {
    let mut report = String::new();
    writeln!(report, "Roam MetricKit Crash Diagnostics")?;
    writeln!(report, "================================")?;
    writeln!(report)?;
    writeln!(
        report,
        "Payload window: {} -> {}",
        payload.time_stamp_begin.as_deref().unwrap_or("unknown"),
        payload.time_stamp_end.as_deref().unwrap_or("unknown")
    )?;
    writeln!(
        report,
        "Install: user_id={} build={} release={} platform={} os={} locale={}",
        installation_info.user_id.as_deref().unwrap_or("unknown"),
        installation_info
            .build_version
            .as_deref()
            .unwrap_or("unknown"),
        installation_info
            .release_version
            .as_deref()
            .unwrap_or("unknown"),
        installation_info
            .os_platform
            .as_deref()
            .unwrap_or("unknown"),
        installation_info.os_version.as_deref().unwrap_or("unknown"),
        installation_info
            .user_locale
            .as_deref()
            .unwrap_or("unknown")
    )?;
    writeln!(
        report,
        "Diagnostics: logs={} debug_errors={} devices={}",
        diagnostics.logs.len(),
        diagnostics.debug_errors.len(),
        diagnostics.devices.len()
    )?;
    writeln!(report)?;

    if !lookup_errors.is_empty() {
        let binary_names = payload.binary_names_by_breakpad_id();
        writeln!(report, "Unresolved UUIDs")?;
        for (breakpad_id, error) in lookup_errors {
            let name = binary_names
                .get(breakpad_id)
                .map(|name| format!(" ({name})"))
                .unwrap_or_default();
            writeln!(
                report,
                "- {breakpad_id}{name}: {}",
                summarize_lookup_error(error)
            )?;
        }
        writeln!(report)?;
    }

    for (crash_index, crash) in payload.crash_diagnostics.iter().enumerate() {
        writeln!(
            report,
            "Crash {}{}",
            crash_index + 1,
            crash
                .version
                .as_deref()
                .map(|version| format!(" (version {version})"))
                .unwrap_or_default()
        )?;

        // Surface the termination fields above the metadata dump. They are the
        // ones that say whether the OS killed the process and why, and they are
        // easy to miss inside an alphabetical key/value list.
        let termination_reason = crash.termination_reason();
        let region_info = crash.virtual_memory_region_info();
        let stack_overflow = region_info
            .as_deref()
            .is_some_and(faulting_address_is_in_stack_guard);
        if let Some(termination_reason) = termination_reason.as_deref() {
            writeln!(report, "Termination reason: {termination_reason}")?;
        }
        if let Some(diagnosis) = describe_termination(
            &crash.diagnostic_meta_data,
            termination_reason.as_deref(),
            region_info.as_deref(),
        ) {
            writeln!(report, "Diagnosis: {diagnosis}")?;
        }
        if let Some(region_info) = region_info.as_deref() {
            writeln!(report, "Faulting VM region: {region_info}")?;
        }

        if !crash.diagnostic_meta_data.is_empty() {
            writeln!(report, "Metadata:")?;
            for (key, value) in &crash.diagnostic_meta_data {
                writeln!(report, "  {key}: {}", render_json_scalar(value))?;
            }
        }

        render_threads(
            &mut report,
            crash,
            " (attributed - this is the thread that crashed)",
            stack_overflow,
            symbolicated_addresses,
            lookup_errors,
        )?;
    }

    // After every crash and before the trailing sections, which
    // `crash_records::without_hangs` relies on to cut them back out.
    for (hang_index, hang) in payload.hang_diagnostics.iter().enumerate() {
        writeln!(
            report,
            "Hang {}{}",
            hang_index + 1,
            hang.version
                .as_deref()
                .map(|version| format!(" (version {version})"))
                .unwrap_or_default()
        )?;
        if let Some(duration) = metadata_string(&hang.diagnostic_meta_data, "hangDuration") {
            writeln!(report, "Hang duration: {duration}")?;
        }
        if !hang.diagnostic_meta_data.is_empty() {
            writeln!(report, "Metadata:")?;
            for (key, value) in &hang.diagnostic_meta_data {
                writeln!(report, "  {key}: {}", render_json_scalar(value))?;
            }
        }
        render_threads(
            &mut report,
            hang,
            " (attributed - the thread that hung, sampled across the hang)",
            false,
            symbolicated_addresses,
            lookup_errors,
        )?;
    }

    render_faulting_thread_backtraces(&mut report, diagnostics)?;
    render_debug_errors(&mut report, diagnostics)?;
    render_logs(&mut report, diagnostics, payload)?;

    Ok(report)
}

fn render_threads(
    report: &mut String,
    diagnostic: &MetricKitCrashDiagnostic,
    attributed_label: &str,
    stack_overflow: bool,
    symbolicated_addresses: &BTreeMap<String, LookedUpAddresses>,
    lookup_errors: &BTreeMap<String, String>,
) -> Result<()> {
    let call_stacks = &diagnostic.call_stack_tree.call_stacks;
    if !call_stacks.is_empty() {
        writeln!(report, "Threads (frame 0 is innermost):")?;
    }
    for (stack_index, call_stack) in call_stacks.iter().enumerate() {
        writeln!(
            report,
            "Thread {}{}:",
            stack_index,
            if call_stack.thread_attributed {
                attributed_label
            } else {
                ""
            }
        )?;
        if call_stack.call_stack_root_frames.is_empty() {
            // An empty thread means the unwinder produced no frames, which
            // on the attributed thread makes the report unusable. Say so
            // rather than printing a blank line.
            writeln!(report, "  (no frames - MetricKit captured no backtrace)")?;
            if call_stack.thread_attributed && stack_overflow {
                writeln!(
                    report,
                    "  The crash is a stack overflow, and MetricKit unwinds in-process: \
                     there was no stack left to walk, so the frames that would name the \
                     runaway call are unrecoverable from this payload."
                )?;
            }
        } else {
            let mut next_index = 0usize;
            render_call_stack(
                report,
                &call_stack.call_stack_root_frames,
                0,
                &mut next_index,
                symbolicated_addresses,
                lookup_errors,
            )?;
        }
        writeln!(report)?;
    }
    Ok(())
}

/// The app's own backtrace of the faulting thread.
///
/// Rendered below the threads because for a stack overflow it is the thread:
/// MetricKit's unwinder gives up on a blown stack and reports zero frames.
fn render_faulting_thread_backtraces(
    report: &mut String,
    diagnostics: &RoamDebugInfo,
) -> Result<()> {
    let Some(backtraces) = diagnostics.faulting_thread_backtraces.as_ref() else {
        return Ok(());
    };
    let backtraces: Vec<&String> = backtraces.iter().filter(|t| !t.trim().is_empty()).collect();
    if backtraces.is_empty() {
        return Ok(());
    }

    writeln!(
        report,
        "In-process backtrace of the faulting thread ({})",
        backtraces.len()
    )?;
    writeln!(
        report,
        "Captured in the run that died, by the app's own SIGSEGV/SIGBUS handler on an \
         alternate signal stack, or by its uncaught-exception handler at the throw site. \
         Unlike the MetricKit call stacks above this survives a stack overflow - a frame \
         repeating down this list is the recursion."
    )?;
    for backtrace in backtraces {
        for line in backtrace.lines() {
            writeln!(report, "  {}", demangle_backtrace_line(line))?;
        }
    }
    writeln!(report)?;
    Ok(())
}

/// Demangle the symbol in one `backtrace_symbols` line.
///
/// The app captures this stack in its `SIGSEGV` handler, where demangling
/// would allocate on an alternate signal stack, so it emits raw linker names
/// and the demangling happens here.
///
/// [`crate::crash_rules`] matches on demangled names, and for a stack overflow
/// this is the only stack in the report, so leaving it raw makes every
/// recursion crash miss its rule.
///
/// `backtrace_symbols` renders `index image address symbol + offset`. Anything
/// that does not parse is passed through untouched.
fn demangle_backtrace_line(line: &str) -> String {
    // Split after the hex address so the image name, which needs no demangling
    // and may repeat as the fallback symbol, cannot be mistaken for the symbol.
    let Some(address_start) = line.find("0x") else {
        return line.to_string();
    };
    let after_address = &line[address_start..];
    let Some(gap) = after_address.find(char::is_whitespace) else {
        return line.to_string();
    };
    let (prefix, rest) = line.split_at(address_start + gap);
    let symbol = rest.trim_start();
    if symbol.is_empty() {
        return line.to_string();
    }
    let padding = &rest[..rest.len() - symbol.len()];

    // The trailing ` + 1033388` is the offset into the symbol, not part of it.
    let (symbol, offset) = match symbol.rsplit_once(" + ") {
        Some((symbol, offset)) if offset.bytes().all(|b| b.is_ascii_digit()) => {
            (symbol, Some(offset))
        }
        _ => (symbol, None),
    };

    let mut out = format!("{prefix}{padding}{}", demangle_symbol(symbol));
    if let Some(offset) = offset {
        out.push_str(" + ");
        out.push_str(offset);
    }
    out
}

fn render_debug_errors(report: &mut String, diagnostics: &RoamDebugInfo) -> Result<()> {
    if diagnostics.debug_errors.is_empty() {
        return Ok(());
    }
    writeln!(report, "Debug errors ({})", diagnostics.debug_errors.len())?;
    for error in &diagnostics.debug_errors {
        // These are multi-line Swift error dumps; indent continuations so the
        // section stays scannable.
        for (index, line) in error.lines().enumerate() {
            let bullet = if index == 0 { "- " } else { "  " };
            writeln!(report, "{bullet}{line}")?;
        }
    }
    writeln!(report)?;
    Ok(())
}

/// Longest log block we will paste into a report, in entries and in bytes.
/// The crash report is a Discord attachment people read top to bottom, so the
/// cap is about readability rather than transport.
const MAX_LOG_ENTRIES: usize = 2000;
const MAX_LOG_BYTES: usize = 256 * 1024;
/// Individual `os_log` messages can carry a whole HTTP body; keep the tail of
/// the block reachable.
const MAX_LOG_MESSAGE_CHARS: usize = 2000;

/// Render the captured `os_log` entries, newest last.
///
/// The app collects these with `OSLogStore(scope: .currentProcessIdentifier)`
/// when `MXMetricManager` hands over the payload. MetricKit delivers payloads
/// on a later launch, so these lines describe the reporting process, not the
/// one that crashed. Print both windows so that is visible.
fn render_logs(
    report: &mut String,
    diagnostics: &RoamDebugInfo,
    payload: &MetricKitPayload,
) -> Result<()> {
    if diagnostics.logs.is_empty() {
        writeln!(report, "Logs (none captured)")?;
        return Ok(());
    }

    // The device collects with `.reverse`, so the array arrives newest first.
    // Sort rather than reverse: the order is the app's choice, not a contract.
    let mut entries: Vec<&LogEntry> = diagnostics.logs.iter().collect();
    entries.sort_by_key(|entry| entry.timestamp);

    let total = entries.len();
    let window = match (entries.first(), entries.last()) {
        (Some(first), Some(last)) => format!(
            " {} -> {}",
            first.timestamp.format("%Y-%m-%d %H:%M:%S%.3fZ"),
            last.timestamp.format("%Y-%m-%d %H:%M:%S%.3fZ")
        ),
        _ => String::new(),
    };

    // With the app's own file log, an upload replays the dead run's lines and
    // tags them. Older builds still send the reporting process's log, which is
    // the launch after the crash.
    let from_crashed_run = entries
        .iter()
        .filter(|entry| entry.source.as_deref() == Some("previous-run"))
        .count();

    writeln!(report, "Logs ({total} entries,{window})")?;
    if from_crashed_run == total {
        writeln!(
            report,
            "Replayed from the app's own file log for the run that crashed (crash window: {} -> \
             {}). These are pre-crash lines.",
            payload.time_stamp_begin.as_deref().unwrap_or("unknown"),
            payload.time_stamp_end.as_deref().unwrap_or("unknown")
        )?;
    } else if from_crashed_run > 0 {
        writeln!(
            report,
            "{from_crashed_run} of {total} entries were replayed from the crashed run's file log \
             (crash window: {} -> {}); the rest are from the process that reported the crash.",
            payload.time_stamp_begin.as_deref().unwrap_or("unknown"),
            payload.time_stamp_end.as_deref().unwrap_or("unknown")
        )?;
    } else {
        writeln!(
            report,
            "Captured when MetricKit delivered the payload (crash window: {} -> {}), from this \
             process only. A log window that starts after the crash is from a later launch and \
             says nothing about what crashed.",
            payload.time_stamp_begin.as_deref().unwrap_or("unknown"),
            payload.time_stamp_end.as_deref().unwrap_or("unknown")
        )?;
    }

    // Keep the newest entries: whatever the app was doing last is the part
    // worth reading, and it is the part a byte cap would otherwise cut.
    let dropped_for_count = total.saturating_sub(MAX_LOG_ENTRIES);
    let kept = &entries[dropped_for_count..];

    let mut rendered: Vec<String> = Vec::with_capacity(kept.len());
    let mut bytes = 0usize;
    let mut dropped_for_bytes = 0usize;
    for entry in kept.iter().rev() {
        let line = format_log_entry(entry);
        if bytes + line.len() > MAX_LOG_BYTES && !rendered.is_empty() {
            dropped_for_bytes = kept.len() - rendered.len();
            break;
        }
        bytes += line.len();
        rendered.push(line);
    }
    rendered.reverse();

    let dropped = dropped_for_count + dropped_for_bytes;
    if dropped > 0 {
        writeln!(
            report,
            "  ... {dropped} older entr{} omitted",
            if dropped == 1 { "y" } else { "ies" }
        )?;
    }
    for line in rendered {
        report.push_str(&line);
    }
    writeln!(report)?;
    Ok(())
}

fn format_log_entry(entry: &LogEntry) -> String {
    let mut out = String::new();
    let level = entry.level.as_deref().unwrap_or("-");
    let category = entry.category.as_deref().unwrap_or("-");
    // The subsystem is the app's own for all but a handful of entries, so it
    // only earns a place on the line when it is something else.
    let subsystem = entry
        .subsystem
        .as_deref()
        .filter(|subsystem| !subsystem.starts_with("com.msdrigg."))
        .map(|subsystem| format!("[{subsystem}] "))
        .unwrap_or_default();

    let message: String = if entry.message.chars().count() > MAX_LOG_MESSAGE_CHARS {
        let truncated: String = entry.message.chars().take(MAX_LOG_MESSAGE_CHARS).collect();
        format!("{truncated}… (truncated)")
    } else {
        entry.message.clone()
    };

    let prefix = format!(
        "  {}  {level:<8} {category:<15} ",
        entry.timestamp.format("%H:%M:%S%.3f")
    );
    for (index, line) in message.lines().enumerate() {
        if index == 0 {
            out.push_str(&format!("{prefix}{subsystem}{line}\n"));
        } else {
            // Continuations line up under the message column.
            out.push_str(&format!("{:width$}{line}\n", "", width = prefix.len()));
        }
    }
    if message.is_empty() {
        out.push_str(&format!("{prefix}{subsystem}\n"));
    }
    out
}

/// Render one thread's frames.
///
/// MetricKit nests each caller inside its callee's `subFrames`, so a crash
/// thread arrives as a chain from the innermost frame to `thread_start`.
/// Printed flat and numbered with frame 0 innermost, matching Apple's crash
/// reports. Aggregated trees can branch, so indent only there.
fn render_call_stack(
    report: &mut String,
    frames: &[MetricKitCallStackFrame],
    branch_depth: usize,
    next_index: &mut usize,
    symbolicated_addresses: &BTreeMap<String, LookedUpAddresses>,
    lookup_errors: &BTreeMap<String, String>,
) -> Result<()> {
    // Explicit stack rather than recursion: with the parse depth cap lifted,
    // recursing here would overflow on the deep trees this exists to render.
    //
    // Each entry carries the frame, its indent depth, and the depth its
    // children inherit. Children only indent where the level branched, so the
    // child depth is fixed by the sibling list.
    let mut stack: Vec<(&MetricKitCallStackFrame, usize, usize)> = Vec::new();
    let child_depth = if frames.len() > 1 {
        branch_depth + 1
    } else {
        branch_depth
    };
    // Pushed in reverse so siblings pop in source order.
    for frame in frames.iter().rev() {
        stack.push((frame, branch_depth, child_depth));
    }

    while let Some((frame, depth, child_depth)) = stack.pop() {
        let index = *next_index;
        *next_index += 1;

        let indent = "  ".repeat(depth + 1);
        let binary_name = frame.binary_name.as_deref().unwrap_or("<unknown>");
        let offset = frame
            .offset_into_binary_text_segment
            .map(|offset| format!("+0x{offset:x}"))
            .unwrap_or_else(|| "+?".to_string());
        let symbol = frame_symbol(frame, symbolicated_addresses, lookup_errors);
        let sample_count = frame
            .sample_count
            .map(|count| format!(" samples={count}"))
            .unwrap_or_default();

        writeln!(
            report,
            "{indent}{index:<3} {binary_name:<28} {offset:<12} {symbol}{sample_count}"
        )?;

        let grandchild_depth = if frame.sub_frames.len() > 1 {
            child_depth + 1
        } else {
            child_depth
        };
        // Children go on top of the stack so they render immediately after
        // this frame, keeping the numbering depth-first like the recursion did.
        for sub_frame in frame.sub_frames.iter().rev() {
            stack.push((sub_frame, child_depth, grandchild_depth));
        }
    }

    Ok(())
}

fn frame_symbol(
    frame: &MetricKitCallStackFrame,
    symbolicated_addresses: &BTreeMap<String, LookedUpAddresses>,
    lookup_errors: &BTreeMap<String, String>,
) -> String {
    let Some(binary_uuid) = frame.binary_uuid.as_deref() else {
        return "(missing UUID)".to_string();
    };
    let Some(breakpad_id) = binary_uuid_to_breakpad_id(binary_uuid) else {
        return format!("({binary_uuid})");
    };
    let Some(offset) = frame
        .offset_into_binary_text_segment
        .and_then(|offset| u32::try_from(offset).ok())
    else {
        return format!("({binary_uuid}, offset unavailable)");
    };

    if let Some(results) = symbolicated_addresses.get(&breakpad_id) {
        if let Some(Some(result)) = results.address_results.get(&offset) {
            let mut symbol = demangle_symbol(&result.symbol_name);
            if let Some(frames) = &result.inline_frames
                && let Some(frame) = frames.first()
                && let Some(location) = render_debug_frame_location(frame)
            {
                symbol.push_str(" at ");
                symbol.push_str(&location);
            }
            return symbol;
        }
        return format!("(no symbol for {binary_uuid} +0x{offset:x})");
    }

    // Not the lookup error: samply reports one line per candidate path per
    // cache, so it is printed once in the "Unresolved UUIDs" section.
    let _ = lookup_errors;
    format!("(unresolved {binary_uuid})")
}

/// Replaces `<redacted>`, `fun_<start>` and missing names for system images
/// with the private names in the cache's `.symbols` subcache. Returns how many
/// addresses it named.
fn apply_local_symbols(
    dyld_dir: &Path,
    arch: Option<&str>,
    results: &mut BTreeMap<String, LookedUpAddresses>,
) -> Result<usize> {
    let Some(local) = DyldLocalSymbols::open(dyld_dir, arch)? else {
        return Ok(0);
    };
    let mut named = 0;
    for (breakpad_id, result) in results.iter_mut() {
        let Some(uuid) = breakpad_id
            .get(..32)
            .and_then(|hex| Uuid::parse_str(hex).ok())
        else {
            continue;
        };
        if !local.has_image(&uuid) {
            continue;
        }
        let wanted: Vec<u32> = result
            .address_results
            .iter()
            .filter(|(_, found)| match found {
                None => true,
                Some(found) => {
                    found.inline_frames.is_none()
                        && (found.symbol_name == "<redacted>"
                            || found.symbol_name.starts_with("fun_"))
                }
            })
            .map(|(&address, _)| address)
            .collect();
        if wanted.is_empty() {
            continue;
        }
        for (address, symbol) in local.lookup(&uuid, &wanted)? {
            let current = result.address_results[&address]
                .as_ref()
                .map(|found| found.symbol_name.as_str());
            if local_name_applies(current, &symbol) {
                result.add_address_symbol(address, symbol.name);
                named += 1;
            }
        }
    }
    Ok(named)
}

fn demangle_symbol(symbol: &str) -> String {
    Name::from(symbol)
        .try_demangle(DemangleOptions::name_only())
        .into_owned()
}

fn render_debug_frame_location(frame: &FrameDebugInfo) -> Option<String> {
    let path = frame.file_path.as_ref()?.display_path();
    match frame.line_number {
        Some(line) => Some(format!("{path}:{line}")),
        None => Some(path),
    }
}

fn render_json_scalar(value: &serde_json::Value) -> String {
    match value {
        serde_json::Value::String(value) => value.clone(),
        _ => value.to_string(),
    }
}

fn sanitize_cache_component(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '.' | '-' | '_') {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

fn extract_zip_archive<R: Read + Seek>(dsym_zip: R, extracted_root: &Path) -> Result<()> {
    let mut archive = zip::ZipArchive::new(dsym_zip).context("opening dSYM zip archive")?;
    for index in 0..archive.len() {
        let mut file = archive
            .by_index(index)
            .with_context(|| format!("reading zip entry {index}"))?;
        let Some(enclosed_name) = file.enclosed_name() else {
            tracing::warn!(entry = ?file.name(), "Skipping unsafe zip entry path");
            continue;
        };
        let out_path = extracted_root.join(enclosed_name);
        if file.is_dir() {
            fs::create_dir_all(&out_path)
                .with_context(|| format!("creating directory {}", out_path.display()))?;
            continue;
        }

        if let Some(parent) = out_path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("creating directory {}", parent.display()))?;
        }

        let mut out_file = File::create(&out_path)
            .with_context(|| format!("creating extracted file {}", out_path.display()))?;
        std::io::copy(&mut file, &mut out_file)
            .with_context(|| format!("extracting zip entry to {}", out_path.display()))?;
    }
    Ok(())
}

fn find_dwarf_files(root: &Path) -> Result<Vec<PathBuf>> {
    let mut result = Vec::new();
    find_dwarf_files_impl(root, &mut result, false)?;
    Ok(result)
}

fn find_dwarf_files_impl(path: &Path, result: &mut Vec<PathBuf>, inside_dsym: bool) -> Result<()> {
    let metadata = fs::metadata(path).with_context(|| format!("reading {}", path.display()))?;
    if metadata.is_file() {
        if path
            .components()
            .collect::<Vec<_>>()
            .windows(4)
            .any(|window| {
                window[0].as_os_str().to_string_lossy().ends_with(".dSYM")
                    && window[1].as_os_str() == "Contents"
                    && window[2].as_os_str() == "Resources"
                    && window[3].as_os_str() == "DWARF"
            })
        {
            result.push(path.to_path_buf());
        }
        return Ok(());
    }

    if metadata.is_dir() {
        let is_dsym = path
            .file_name()
            .is_some_and(|name| name.to_string_lossy().ends_with(".dSYM"));
        // Nested `.dSYM` directories are build-tool detritus, and walking them
        // feeds non-Mach-O files to the UUID reader.
        if is_dsym && inside_dsym {
            return Ok(());
        }
        for entry in fs::read_dir(path).with_context(|| format!("reading {}", path.display()))? {
            let entry = entry?;
            find_dwarf_files_impl(&entry.path(), result, inside_dsym || is_dsym)?;
        }
    }

    Ok(())
}

fn debug_ids_for_macho(path: &Path) -> Result<Vec<DebugId>> {
    let data = fs::read(path).with_context(|| format!("reading {}", path.display()))?;
    let ids = match FileKind::parse(&*data).context("parsing object file kind")? {
        FileKind::MachOFat32 => {
            let fat = MachOFatFile32::parse(&*data).context("parsing fat Mach-O file")?;
            fat.arches()
                .iter()
                .filter_map(|arch| debug_id_for_macho_data(arch.data(&*data).ok()?))
                .collect()
        }
        FileKind::MachOFat64 => {
            let fat = MachOFatFile64::parse(&*data).context("parsing fat64 Mach-O file")?;
            fat.arches()
                .iter()
                .filter_map(|arch| debug_id_for_macho_data(arch.data(&*data).ok()?))
                .collect()
        }
        _ => debug_id_for_macho_data(&data).into_iter().collect(),
    };
    Ok(ids)
}

fn debug_id_for_macho_data(data: &[u8]) -> Option<DebugId> {
    let object = object::File::parse(data).ok()?;
    let uuid = object.mach_uuid().ok()??;
    Some(DebugId::from_uuid(Uuid::from_bytes(uuid)))
}

fn index_debug_file(symbolication_root: &Path, debug_id: DebugId, dwarf_file: &Path) -> Result<()> {
    let by_debug_id = symbolication_root
        .join("cache")
        .join("by-debug-id")
        .join(debug_id.breakpad().to_string());
    let by_uuid = symbolication_root
        .join("cache")
        .join("by-uuid")
        .join(debug_id.uuid().to_string().to_ascii_uppercase());

    link_or_copy_debug_file(dwarf_file, &by_debug_id)?;
    link_or_copy_debug_file(dwarf_file, &by_uuid)?;
    Ok(())
}

fn link_or_copy_debug_file(source: &Path, destination: &Path) -> Result<()> {
    if let Some(parent) = destination.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("creating dSYM cache directory {}", parent.display()))?;
    }

    if destination.exists() || fs::symlink_metadata(destination).is_ok() {
        fs::remove_file(destination)
            .with_context(|| format!("replacing cached dSYM {}", destination.display()))?;
    }

    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(source, destination).with_context(|| {
            format!(
                "linking dSYM cache {} -> {}",
                destination.display(),
                source.display()
            )
        })?;
    }

    #[cfg(not(unix))]
    {
        fs::copy(source, destination).with_context(|| {
            format!(
                "copying dSYM cache {} -> {}",
                source.display(),
                destination.display()
            )
        })?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_os_build_id_from_metri_kit_os_version() {
        assert_eq!(
            parse_os_build_id("macOS 15.5 (24F74)").as_deref(),
            Some("24F74")
        );
        assert_eq!(
            parse_os_build_id("iOS 18.4.1 (22E252)").as_deref(),
            Some("22E252")
        );
        assert_eq!(parse_os_build_id("iOS 18.4.1"), None);
    }

    #[test]
    fn parses_os_family_from_metri_kit_os_version() {
        assert_eq!(
            parse_os_family("macOS 15.5 (24F74)").as_deref(),
            Some("macOS")
        );
        assert_eq!(
            parse_os_family("iOS 18.4.1 (22E252)").as_deref(),
            Some("iOS")
        );
        assert_eq!(parse_os_family(""), None);

        // The spelling MetricKit actually emits for an iPhone. Tokenizing on
        // whitespace gave "iPhone", which appledb rejects - so its fallback had
        // never worked for the platform that produces most of our crashes.
        assert_eq!(
            parse_os_family("iPhone OS 26.6 (23G71)").as_deref(),
            Some("iOS")
        );
        assert_eq!(
            parse_os_family("iPadOS 26.5 (23F84)").as_deref(),
            Some("iPadOS")
        );
        assert_eq!(
            parse_os_family("Mac OS X 10.15.7 (19H2)").as_deref(),
            Some("macOS")
        );
        assert_eq!(
            parse_os_family("watchOS 11.2 (22S100)").as_deref(),
            Some("watchOS")
        );

        // Every value returned must be one appledb will accept, or the download
        // fails on the flag before it ever reaches the network.
        const APPLEDB_CHOICES: &[&str] = &[
            "audioOS", "bridgeOS", "iOS", "iPadOS", "iPodOS", "macOS", "tvOS", "watchOS",
        ];
        for version in [
            "iPhone OS 26.6 (23G71)",
            "iPadOS 26.5 (23F84)",
            "macOS 15.5 (24F74)",
            "Mac OS X 10.15.7 (19H2)",
            "watchOS 11.2 (22S100)",
            "tvOS 18.0 (22J356)",
        ] {
            let family = parse_os_family(version).expect(version);
            assert!(
                APPLEDB_CHOICES.contains(&family.as_str()),
                "{version} produced {family}, which appledb does not accept"
            );
        }

        // Unrecognized families are skipped rather than guessed at.
        assert_eq!(parse_os_family("visionOS 2.0 (22N320)"), None);
    }

    fn crash_from(value: serde_json::Value) -> MetricKitCrashDiagnostic {
        serde_json::from_value(value).expect("crash diagnostic deserializes")
    }

    #[test]
    fn parses_termination_code_from_reason_string() {
        assert_eq!(
            parse_termination_code("Namespace SPRINGBOARD, Code 0xdead10cc"),
            Some(0xdead10cc)
        );
        assert_eq!(
            parse_termination_code("Namespace ASSERTIOND, Code 0x8badf00d"),
            Some(0x8badf00d)
        );
        // Trailing prose after the code must not be swallowed into the digits.
        assert_eq!(
            parse_termination_code("Namespace SPRINGBOARD, Code 0xdead10cc (held lock)"),
            Some(0xdead10cc)
        );
        assert_eq!(parse_termination_code("Namespace SPRINGBOARD"), None);
        assert_eq!(parse_termination_code("Code 0x"), None);
    }

    #[test]
    fn reads_termination_reason_from_either_placement() {
        // Top-level, mirroring MXCrashDiagnostic's property layout.
        let top_level = crash_from(serde_json::json!({
            "callStackTree": { "callStacks": [] },
            "terminationReason": "Namespace SPRINGBOARD, Code 0xdead10cc",
            "virtualMemoryRegionInfo": "0x1234 is in region 5",
            "diagnosticMetaData": {}
        }));
        assert_eq!(
            top_level.termination_reason().as_deref(),
            Some("Namespace SPRINGBOARD, Code 0xdead10cc")
        );
        assert_eq!(
            top_level.virtual_memory_region_info().as_deref(),
            Some("0x1234 is in region 5")
        );

        // Folded into diagnosticMetaData, which is what jsonRepresentation() does.
        let in_metadata = crash_from(serde_json::json!({
            "callStackTree": { "callStacks": [] },
            "diagnosticMetaData": {
                "terminationReason": "Namespace SPRINGBOARD, Code 0xdead10cc"
            }
        }));
        assert_eq!(
            in_metadata.termination_reason().as_deref(),
            Some("Namespace SPRINGBOARD, Code 0xdead10cc")
        );

        // Absent entirely - the case every payload we have on file hits today.
        let absent = crash_from(serde_json::json!({
            "callStackTree": { "callStacks": [] },
            "diagnosticMetaData": { "signal": 9 }
        }));
        assert_eq!(absent.termination_reason(), None);
        assert_eq!(absent.virtual_memory_region_info(), None);
    }

    #[test]
    fn describes_termination_with_decoded_reason() {
        let crash = crash_from(serde_json::json!({
            "callStackTree": { "callStacks": [] },
            "diagnosticMetaData": { "exceptionType": 10, "signal": 9 },
            "terminationReason": "Namespace SPRINGBOARD, Code 0xdead10cc"
        }));

        let description = describe_termination(
            &crash.diagnostic_meta_data,
            crash.termination_reason().as_deref(),
            crash.virtual_memory_region_info().as_deref(),
        )
        .expect("description");

        assert!(description.contains("EXC_CRASH (10)"), "{description}");
        assert!(description.contains("SIGKILL (9)"), "{description}");
        assert!(description.contains("0xdead10cc"), "{description}");
        assert!(
            description.contains("shared app-group container"),
            "{description}"
        );
    }

    #[test]
    fn describes_os_kill_without_a_termination_reason() {
        // The shape of the payload that prompted this: EXC_CRASH + SIGKILL and
        // no terminationReason, so the policy can be narrowed but not confirmed.
        let crash = crash_from(serde_json::json!({
            "callStackTree": { "callStacks": [] },
            "diagnosticMetaData": { "exceptionType": 10, "signal": 9 }
        }));

        let description = describe_termination(
            &crash.diagnostic_meta_data,
            crash.termination_reason().as_deref(),
            crash.virtual_memory_region_info().as_deref(),
        )
        .expect("description");

        assert!(description.contains("killed by the OS"), "{description}");
        assert!(description.contains("unconfirmed"), "{description}");
        assert!(description.contains("0xdead10cc"), "{description}");
    }

    #[test]
    fn describes_termination_from_string_encoded_numbers() {
        // MetricKit has shipped these as strings as well as numbers.
        let crash = crash_from(serde_json::json!({
            "callStackTree": { "callStacks": [] },
            "diagnosticMetaData": { "exceptionType": "1", "signal": "11" }
        }));

        let description = describe_termination(
            &crash.diagnostic_meta_data,
            crash.termination_reason().as_deref(),
            crash.virtual_memory_region_info().as_deref(),
        )
        .expect("description");

        assert_eq!(description, "EXC_BAD_ACCESS (1) / SIGSEGV (11)");
    }

    #[test]
    fn describes_nothing_without_termination_fields() {
        let crash = crash_from(serde_json::json!({
            "callStackTree": { "callStacks": [] },
            "diagnosticMetaData": { "deviceType": "iPhone14,7" }
        }));

        assert_eq!(
            describe_termination(
                &crash.diagnostic_meta_data,
                crash.termination_reason().as_deref(),
                crash.virtual_memory_region_info().as_deref(),
            ),
            None
        );
    }

    #[test]
    fn report_surfaces_termination_reason_above_metadata() {
        let payload: MetricKitPayload = serde_json::from_value(serde_json::json!({
            "timeStampBegin": "2026-08-10 15:53:00",
            "timeStampEnd": "2026-08-10 15:53:00",
            "crashDiagnostics": [{
                "version": "1.0.0",
                "callStackTree": { "callStacks": [] },
                "terminationReason": "Namespace SPRINGBOARD, Code 0xdead10cc",
                "diagnosticMetaData": {
                    "exceptionType": 10,
                    "signal": 9,
                    "deviceType": "iPhone14,7"
                }
            }]
        }))
        .expect("payload deserializes");

        let report = render_metric_report(
            &empty_diagnostics(),
            &empty_device_info(),
            &payload,
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(
            report.contains("Termination reason: Namespace SPRINGBOARD, Code 0xdead10cc"),
            "{report}"
        );
        assert!(
            report.contains("Diagnosis: EXC_CRASH (10) / SIGKILL (9)"),
            "{report}"
        );
        assert!(report.contains("shared app-group container"), "{report}");

        // The decoded lines must come before the raw key/value dump.
        let diagnosis_at = report.find("Diagnosis:").expect("diagnosis line");
        let metadata_at = report.find("Metadata:").expect("metadata block");
        assert!(diagnosis_at < metadata_at, "{report}");
    }

    #[test]
    fn report_renders_hangs_after_crashes() {
        let payload: MetricKitPayload = serde_json::from_value(serde_json::json!({
            "timeStampBegin": "2026-10-12 14:12:00",
            "timeStampEnd": "2026-10-12 14:12:00",
            "crashDiagnostics": [{
                "version": "1.0.0",
                "callStackTree": { "callStacks": [] },
                "diagnosticMetaData": { "exceptionType": 10, "signal": 9 }
            }],
            "hangDiagnostics": [{
                "version": "1.0.0",
                "callStackTree": {
                    "callStackPerThread": true,
                    "callStacks": [{
                        "threadAttributed": true,
                        "callStackRootFrames": [{
                            "binaryName": "SwiftUICore",
                            "offsetIntoBinaryTextSegment": 4096,
                            "sampleCount": 18,
                            "subFrames": []
                        }]
                    }]
                },
                "diagnosticMetaData": { "hangDuration": "9.25 sec", "appVersion": "1.59" }
            }]
        }))
        .expect("payload deserializes");
        assert_eq!(payload.diagnostics().count(), 2);

        let report = render_metric_report(
            &empty_diagnostics(),
            &empty_device_info(),
            &payload,
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(
            report.contains("Hang 1 (version 1.0.0)\nHang duration: 9.25 sec\n"),
            "{report}"
        );
        assert!(report.contains("the thread that hung"), "{report}");
        assert!(report.contains("samples=18"), "{report}");
        let crash_at = report.find("Crash 1").expect("crash section");
        let hang_at = report.find("Hang 1").expect("hang section");
        let logs_at = report.find("Logs (").expect("logs section");
        assert!(crash_at < hang_at && hang_at < logs_at, "{report}");
        assert_eq!(crate::crash_records::parse_report(&report).len(), 1);
    }

    #[test]
    fn report_of_hangs_alone_has_no_crashes() {
        let payload: MetricKitPayload = serde_json::from_value(serde_json::json!({
            "hangDiagnostics": [{
                "callStackTree": { "callStacks": [] },
                "diagnosticMetaData": { "hangDuration": "3 sec", "appVersion": "1.59" }
            }]
        }))
        .expect("payload deserializes");

        let report = render_metric_report(
            &empty_diagnostics(),
            &empty_device_info(),
            &payload,
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(
            report.contains("Hang 1\nHang duration: 3 sec\n"),
            "{report}"
        );
        assert!(
            crate::crash_records::parse_report(&report).is_empty(),
            "{report}"
        );
    }

    /// The `virtualMemoryRegionInfo` from the macOS 26.6.2 crash that motivated
    /// this: the faulting address is 607 bytes below the base of an 8 MB main
    /// thread stack, i.e. inside its guard region.
    const STACK_GUARD_REGION_INFO: &str = "0x16eddbda0 is in 0x16b5d8000-0x16eddc000;  bytes after start: 58736032  bytes before end: 607\n\
         \x20     REGION TYPE                    START - END         [ VSIZE] PRT/MAX SHRMOD  REGION DETAIL\n\
         \x20     MALLOC metadata             13a600000-13a604000    [   16K] rw-/rwx SM=PRV  \n\
         \x20     GAP OF 0x30fd4000 BYTES\n\
         --->  Stack Guard                 16b5d8000-16eddc000    [ 56.0M] ---/rwx SM=PRV  \n\
         \x20     Stack                       16eddc000-16f5d8000    [ 8176K] rw-/rwx SM=SHM  ";

    #[test]
    fn detects_a_stack_overflow_from_the_faulting_vm_region() {
        assert!(faulting_address_is_in_stack_guard(STACK_GUARD_REGION_INFO));

        // The arrow must point at the guard, not merely appear in the map. A
        // fault inside the stack itself is an ordinary bad access.
        let in_stack = STACK_GUARD_REGION_INFO
            .replace("--->  Stack Guard", "      Stack Guard")
            .replace("      Stack     ", "--->  Stack     ");
        assert!(!faulting_address_is_in_stack_guard(&in_stack));
        assert!(!faulting_address_is_in_stack_guard(
            "0x0 is not in any region"
        ));
    }

    #[test]
    fn describes_a_stack_guard_fault_as_a_stack_overflow() {
        let crash = crash_from(serde_json::json!({
            "callStackTree": { "callStacks": [] },
            "diagnosticMetaData": {
                "exceptionType": 1,
                "exceptionCode": 2,
                "signal": 11,
                "virtualMemoryRegionInfo": STACK_GUARD_REGION_INFO
            }
        }));

        let description = describe_termination(
            &crash.diagnostic_meta_data,
            crash.termination_reason().as_deref(),
            crash.virtual_memory_region_info().as_deref(),
        )
        .expect("description");

        assert!(description.contains("EXC_BAD_ACCESS (1)"), "{description}");
        assert!(
            description.contains("KERN_PROTECTION_FAILURE (2)"),
            "{description}"
        );
        assert!(description.contains("SIGSEGV (11)"), "{description}");
        assert!(description.contains("stack overflow"), "{description}");
        assert!(description.contains("unbounded recursion"), "{description}");
    }

    #[test]
    fn report_explains_an_empty_attributed_thread_on_a_stack_overflow() {
        // Exactly the payload shape that produced an unusable report: the
        // crashing thread carries no frames at all.
        let payload: MetricKitPayload = serde_json::from_value(serde_json::json!({
            "crashDiagnostics": [{
                "callStackTree": { "callStacks": [
                    { "threadAttributed": true, "callStackRootFrames": [] },
                    { "callStackRootFrames": [
                        { "binaryName": "AttributeGraph",
                          "binaryUUID": "DDC826E2-4B0E-35CA-AAB1-82A1DC9EA6B4",
                          "offsetIntoBinaryTextSegment": 0xa434,
                          "subFrames": [
                            { "binaryName": "libdispatch.dylib",
                              "binaryUUID": "B2000CD5-F580-314A-A141-E036719D854E",
                              "offsetIntoBinaryTextSegment": 0x1b4b0 }
                          ] }
                    ] }
                ] },
                "diagnosticMetaData": {
                    "exceptionType": 1,
                    "signal": 11,
                    "virtualMemoryRegionInfo": STACK_GUARD_REGION_INFO
                }
            }]
        }))
        .expect("payload deserializes");

        let report = render_metric_report(
            &empty_diagnostics(),
            &empty_device_info(),
            &payload,
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(report.contains("Diagnosis:"), "{report}");
        assert!(report.contains("stack overflow"), "{report}");
        assert!(
            report.contains("Thread 0 (attributed - this is the thread that crashed)"),
            "{report}"
        );
        assert!(report.contains("no frames"), "{report}");
        assert!(report.contains("no stack left to walk"), "{report}");

        // A linear chain must stay flat and numbered rather than stepping one
        // indent level deeper per frame.
        let libdispatch_line = report
            .lines()
            .find(|line| line.contains("libdispatch.dylib"))
            .expect("libdispatch frame");
        let attributegraph_line = report
            .lines()
            .find(|line| line.contains("AttributeGraph"))
            .expect("AttributeGraph frame");
        assert_eq!(
            libdispatch_line.len() - libdispatch_line.trim_start().len(),
            attributegraph_line.len() - attributegraph_line.trim_start().len(),
            "chain frames must share one indent level:\n{report}"
        );
        assert!(
            attributegraph_line.trim_start().starts_with("0 "),
            "{report}"
        );
        assert!(libdispatch_line.trim_start().starts_with("1 "), "{report}");
    }

    #[test]
    fn report_keeps_lookup_errors_out_of_every_frame() {
        // samply's real error text: one line per candidate path, per cache.
        let error = "All candidate paths encountered failures:\n\
             The dyld shared cache file did not include an entry for the dylib at /usr/lib/libxpc.dylib\n\
             The dyld shared cache file did not include an entry for the dylib at /usr/lib/swift/libxpc.dylib\n\
             Unmatched breakpad_id: Expected 00b71270-124e-31fa-b7d2-5d747da4bce1, but received 33e44c2d-d65e-37a6-b85f-1a4cf524a050\n\
             The dyld shared cache file did not include an entry for the dylib at /usr/lib/libxpc.dylib\n\
             Unmatched breakpad_id: Expected a08d6f00-102f-31a3-92d5-e65ac7b776df, but received 33e44c2d-d65e-37a6-b85f-1a4cf524a050";

        let payload: MetricKitPayload = serde_json::from_value(serde_json::json!({
            "crashDiagnostics": [{
                "callStackTree": { "callStacks": [
                    { "threadAttributed": true, "callStackRootFrames": [
                        { "binaryName": "libxpc.dylib",
                          "binaryUUID": "33E44C2D-D65E-37A6-B85F-1A4CF524A050",
                          "offsetIntoBinaryTextSegment": 0x344ec,
                          "subFrames": [
                            { "binaryName": "libxpc.dylib",
                              "binaryUUID": "33E44C2D-D65E-37A6-B85F-1A4CF524A050",
                              "offsetIntoBinaryTextSegment": 0x33bd8 }
                          ] }
                    ] }
                ] },
                "diagnosticMetaData": { "signal": 11 }
            }]
        }))
        .expect("payload deserializes");

        let mut lookup_errors = BTreeMap::new();
        lookup_errors.insert(
            "33E44C2DD65E37A6B85F1A4CF524A0500".to_string(),
            error.to_string(),
        );

        let report = render_metric_report(
            &empty_diagnostics(),
            &empty_device_info(),
            &payload,
            &BTreeMap::new(),
            &lookup_errors,
        )
        .expect("report renders");

        // The candidate-path spam appears nowhere - not per frame, and not in
        // the unresolved section either.
        assert!(
            !report.contains("did not include an entry"),
            "raw candidate-path lines leaked into the report:\n{report}"
        );
        assert!(
            !report.contains("Unmatched breakpad_id"),
            "raw mismatch lines leaked into the report:\n{report}"
        );

        // The unresolved section still says which binary and why, once.
        assert!(
            report.contains("- 33E44C2DD65E37A6B85F1A4CF524A0500 (libxpc.dylib):"),
            "{report}"
        );
        assert!(report.contains("2 cached dyld shared cache(s)"), "{report}");
        assert!(report.contains("3 candidate path(s)"), "{report}");
        // A system library that turned up at other builds must not be
        // misreported as a missing app dSYM.
        assert!(!report.contains("no dSYM on file"), "{report}");

        // Frames name the unresolved UUID and stop there.
        assert_eq!(
            report
                .matches("(unresolved 33E44C2D-D65E-37A6-B85F-1A4CF524A050)")
                .count(),
            2,
            "{report}"
        );
    }

    #[test]
    fn describes_a_swift_runtime_trap() {
        // The iOS 27.0 crash: EXC_BREAKPOINT / SIGTRAP with libswiftCore
        // innermost and no faulting VM region at all.
        let crash = crash_from(serde_json::json!({
            "callStackTree": { "callStacks": [] },
            "diagnosticMetaData": { "exceptionType": 6, "exceptionCode": 1, "signal": 5 }
        }));

        let description = describe_termination(
            &crash.diagnostic_meta_data,
            crash.termination_reason().as_deref(),
            crash.virtual_memory_region_info().as_deref(),
        )
        .expect("description");

        assert!(description.contains("EXC_BREAKPOINT (6)"), "{description}");
        assert!(description.contains("SIGTRAP (5)"), "{description}");
        assert!(description.contains("Swift runtime trap"), "{description}");
        assert!(description.contains("libswiftCore"), "{description}");
        // It must not be described as a memory fault; that sends you hunting
        // for a pointer bug that isn't there.
        assert!(description.contains("not a memory fault"), "{description}");
    }

    /// A trimmed `.map` sidecar in the real format: a mapping table, then one
    /// flush-left install path per dylib followed by indented segment lines.
    /// `AE` and `HIToolbox` cover the nested-framework case; `AppKit` covers
    /// the top-level one.
    const SAMPLE_DYLD_MAP: &str = "\
mapping  EX  544KB 0x180000000 -> 0x180088000
mapping  RW   35MB 0x1E5908000 -> 0x1E7C2C000
/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit
\t          __TEXT 0x180088000 -> 0x181000000
\t    __DATA_CONST 0x1E5908000 -> 0x1E5910000
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/AE.framework/Versions/A/AE
\t          __TEXT 0x1887D5000 -> 0x188848C38
/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox
\t          __TEXT 0x1900A0000 -> 0x190400000
/usr/lib/swift/libswiftCore.dylib
\t          __TEXT 0x1A0000000 -> 0x1A0800000
";

    fn write_cache_with_map(dir: &Path, arch: &str, map: &str) -> PathBuf {
        let cache = dir.join(format!("dyld_shared_cache_{arch}"));
        fs::write(&cache, b"not a real cache").expect("write cache");
        fs::write(dyld_map_path(&cache), map).expect("write map");
        cache
    }

    #[test]
    fn dyld_map_path_appends_rather_than_replacing() {
        // `with_extension` would truncate `x86_64` at the dot-free arch suffix
        // on some names; the sidecar is always the cache name plus `.map`.
        for arch in ["arm64e", "x86_64h", "x86_64"] {
            let cache = PathBuf::from(format!("/data/dyld/dyld_shared_cache_{arch}"));
            assert_eq!(
                dyld_map_path(&cache),
                PathBuf::from(format!("/data/dyld/dyld_shared_cache_{arch}.map"))
            );
        }
    }

    #[test]
    fn parse_dyld_map_indexes_install_paths_by_leaf_name() {
        let temp = tempfile::tempdir().expect("tempdir");
        let map = temp.path().join("cache.map");
        fs::write(&map, SAMPLE_DYLD_MAP).expect("write map");

        let index = parse_dyld_map(&map).expect("parse");

        assert_eq!(
            index.get("AE").map(Vec::as_slice),
            Some(
                ["/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/AE.framework/Versions/A/AE".to_string()]
                    .as_slice()
            )
        );
        assert_eq!(
            index.get("HIToolbox").map(Vec::as_slice),
            Some(
                ["/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox".to_string()]
                    .as_slice()
            )
        );
        assert!(index.contains_key("libswiftCore.dylib"));
        // Indented segment lines are not paths.
        assert!(!index.contains_key("__TEXT"));
        assert!(!index.keys().any(|key| key.contains("mapping")));
    }

    #[test]
    fn nested_subframeworks_resolve_through_the_map() {
        // The bug: `likely_dylib_paths` only ever guesses top-level framework
        // paths, so a framework nested inside another framework was
        // unreachable even with the right cache on disk.
        let temp = tempfile::tempdir().expect("tempdir");
        let cache = write_cache_with_map(temp.path(), "arm64e", SAMPLE_DYLD_MAP);

        let guessed = likely_dylib_paths(&LibraryInfo {
            name: Some("AE".to_string()),
            ..Default::default()
        });
        // Guessing produces a *top-level* `AE.framework`, which does not exist.
        // What it cannot produce is the path nested under CoreServices, which
        // is the one that does.
        assert!(
            !guessed
                .iter()
                .any(|path| path.contains("CoreServices.framework")),
            "guessing must not reach the nested path, or this test proves nothing: {guessed:?}"
        );
        // Exactly the ten guesses whose product with 46 cached shared caches
        // made up the "460 candidate path(s)" in the report.
        assert_eq!(guessed.len(), 10, "{guessed:?}");

        let resolved = resolve_dylib_paths_in_cache(&cache, Some("AE"), &guessed);

        assert_eq!(
            resolved.first().map(String::as_str),
            Some(
                "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/AE.framework/Versions/A/AE"
            ),
            "the looked-up path must be tried before the guesses: {resolved:?}"
        );
        // The guesses stay as fallback.
        for guess in &guessed {
            assert!(resolved.contains(guess), "{guess} dropped: {resolved:?}");
        }
    }

    #[test]
    fn a_cache_without_a_map_still_gets_the_guessed_paths() {
        // The local Cryptexes cache ships no sidecar. Losing the guesses there
        // would trade the nested-framework bug for a worse one.
        let temp = tempfile::tempdir().expect("tempdir");
        let cache = temp.path().join("dyld_shared_cache_arm64e");
        fs::write(&cache, b"not a real cache").expect("write cache");

        let guessed = likely_dylib_paths(&LibraryInfo {
            name: Some("AppKit".to_string()),
            ..Default::default()
        });
        let resolved = resolve_dylib_paths_in_cache(&cache, Some("AppKit"), &guessed);

        assert_eq!(resolved, guessed);
    }

    #[test]
    fn a_name_absent_from_the_map_falls_back_to_the_guesses() {
        let temp = tempfile::tempdir().expect("tempdir");
        let cache = write_cache_with_map(temp.path(), "arm64e", SAMPLE_DYLD_MAP);

        let guessed = likely_dylib_paths(&LibraryInfo {
            name: Some("Roam".to_string()),
            ..Default::default()
        });
        let resolved = resolve_dylib_paths_in_cache(&cache, Some("Roam"), &guessed);

        assert_eq!(resolved, guessed);
    }

    #[test]
    fn a_top_level_framework_is_not_duplicated_by_the_map() {
        // AppKit is reachable both ways. It must be offered once, not twice, or
        // every lookup pays for a redundant candidate against 46 caches.
        let temp = tempfile::tempdir().expect("tempdir");
        let cache = write_cache_with_map(temp.path(), "arm64e", SAMPLE_DYLD_MAP);

        let guessed = likely_dylib_paths(&LibraryInfo {
            name: Some("AppKit".to_string()),
            ..Default::default()
        });
        let resolved = resolve_dylib_paths_in_cache(&cache, Some("AppKit"), &guessed);

        let appkit = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit";
        assert!(guessed.iter().any(|path| path == appkit));
        assert_eq!(
            resolved.iter().filter(|path| *path == appkit).count(),
            1,
            "{resolved:?}"
        );
    }

    #[test]
    fn summarize_lookup_error_names_a_missing_app_dsym() {
        // Roam.debug.dylib will never live in a dyld shared cache, so every
        // candidate path is absent and nothing ever mismatches. That pairing
        // means the dSYM for this build was never uploaded.
        let error = "All candidate paths encountered failures:\n\
             The dyld shared cache file did not include an entry for the dylib at /usr/lib/Roam.debug.dylib\n\
             The dyld shared cache file did not include an entry for the dylib at /usr/lib/swift/Roam.debug.dylib\n\
             The dyld shared cache file did not include an entry for the dylib at /usr/lib/system/Roam.debug.dylib";

        let summary = summarize_lookup_error(error);
        assert!(summary.contains("no dSYM on file"), "{summary}");
        assert!(summary.contains("upload the dSYM for this"), "{summary}");
        assert!(summary.contains("3 candidate path(s)"), "{summary}");
        // Must not claim this is one of our binaries: the same branch fires
        // for a system library the candidate paths could not name.
        assert!(summary.contains("if it is a system library"), "{summary}");
    }

    #[test]
    fn summarize_lookup_error_preserves_unrecognized_reasons() {
        // A missing dSYM or a parse failure is the interesting case; it must
        // survive summarisation verbatim rather than being counted away.
        let summary =
            summarize_lookup_error("symbol lookup panicked: attempt to subtract with overflow");
        assert_eq!(
            summary,
            "symbol lookup panicked: attempt to subtract with overflow"
        );

        // Repeated identical reasons collapse to one.
        let summary = summarize_lookup_error("no dSYM on file\nno dSYM on file\nno dSYM on file");
        assert_eq!(summary, "no dSYM on file");
    }

    fn log_entry(seconds: i64, level: &str, category: &str, message: &str) -> LogEntry {
        LogEntry {
            message: message.to_string(),
            timestamp: chrono::DateTime::from_timestamp(1_786_000_000 + seconds, 0)
                .expect("valid timestamp"),
            level: Some(level.to_string()),
            category: Some(category.to_string()),
            subsystem: Some("com.msdrigg.roam".to_string()),
            source: None,
        }
    }

    fn diagnostics_with_logs(logs: Vec<LogEntry>) -> RoamDebugInfo {
        RoamDebugInfo {
            logs,
            ..empty_diagnostics()
        }
    }

    fn payload_with_window() -> MetricKitPayload {
        serde_json::from_value(serde_json::json!({
            "timeStampBegin": "2026-08-15 09:38:00",
            "timeStampEnd": "2026-08-15 09:38:00",
            "crashDiagnostics": []
        }))
        .expect("payload deserializes")
    }

    #[test]
    fn report_renders_logs_oldest_last() {
        // The device collects with `.reverse`, so the array arrives newest
        // first; the report must not inherit that order.
        let diagnostics = diagnostics_with_logs(vec![
            log_entry(30, "notice", "Backend", "third"),
            log_entry(20, "error", "Network", "second"),
            log_entry(10, "info", "Lifecycle", "first"),
        ]);

        let report = render_metric_report(
            &diagnostics,
            &empty_device_info(),
            &payload_with_window(),
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(report.contains("Logs (3 entries,"), "{report}");
        let first = report.find("first").expect("first entry");
        let second = report.find("second").expect("second entry");
        let third = report.find("third").expect("third entry");
        assert!(first < second && second < third, "{report}");

        // Level and category earn their own columns; the app's own subsystem
        // does not, since every line would carry it.
        assert!(report.contains("error    Network"), "{report}");
        assert!(!report.contains("com.msdrigg.roam"), "{report}");

        // The crash window sits next to the log window so a reader can see
        // whether the lines predate the crash at all.
        assert!(
            report.contains("crash window: 2026-08-15 09:38:00 -> 2026-08-15 09:38:00"),
            "{report}"
        );
    }

    #[test]
    fn report_keeps_the_newest_logs_when_truncating() {
        let logs: Vec<LogEntry> = (0..MAX_LOG_ENTRIES + 50)
            .map(|index| log_entry(index as i64, "notice", "Backend", &format!("entry-{index}")))
            .collect();

        let report = render_metric_report(
            &diagnostics_with_logs(logs),
            &empty_device_info(),
            &payload_with_window(),
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(report.contains("50 older entries omitted"), "{report}");
        // Oldest dropped, newest kept - the tail is the part worth reading.
        assert!(!report.contains("entry-0\n"), "{report}");
        assert!(
            report.contains(&format!("entry-{}", MAX_LOG_ENTRIES + 49)),
            "{report}"
        );
    }

    #[test]
    fn report_notes_when_no_logs_were_captured() {
        let report = render_metric_report(
            &empty_diagnostics(),
            &empty_device_info(),
            &payload_with_window(),
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(report.contains("Logs (none captured)"), "{report}");
    }

    #[test]
    fn report_names_logs_replayed_from_the_crashed_run() {
        // These lines predate the crash, so the report must not repeat the
        // "later launch" warning that applies to a live `OSLogStore` read.
        let diagnostics = diagnostics_with_logs(vec![
            LogEntry {
                source: Some("previous-run".to_string()),
                ..log_entry(20, "notice", "Rendering", "second")
            },
            LogEntry {
                source: Some("previous-run".to_string()),
                ..log_entry(10, "notice", "Rendering", "first")
            },
        ]);

        let report = render_metric_report(
            &diagnostics,
            &empty_device_info(),
            &payload_with_window(),
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(
            report.contains("Replayed from the app's own file log for the run that crashed"),
            "{report}"
        );
        assert!(
            !report.contains("says nothing about what crashed"),
            "{report}"
        );
    }

    #[test]
    fn report_still_warns_when_logs_are_from_the_reporting_process() {
        // An older build, or an upload whose file log was empty, still sends
        // the relaunch's log. That is exactly the case the warning is for.
        let diagnostics = diagnostics_with_logs(vec![log_entry(10, "notice", "Backend", "first")]);

        let report = render_metric_report(
            &diagnostics,
            &empty_device_info(),
            &payload_with_window(),
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(
            report.contains("says nothing about what crashed"),
            "{report}"
        );
        assert!(
            !report.contains("Replayed from the app's own file log"),
            "{report}"
        );
    }

    #[test]
    fn report_renders_the_in_process_faulting_backtrace() {
        let mut diagnostics = empty_diagnostics();
        diagnostics.faulting_thread_backtraces = Some(vec![
            "Fatal access violation, signal 11, at unix time 1786834162\n\
             Backtrace of the faulting thread (innermost first):\n\
             0   Roam  0x0000000102a3c1f0 recurse + 40\n\
             1   Roam  0x0000000102a3c1f0 recurse + 40"
                .to_string(),
        ]);

        let report = render_metric_report(
            &diagnostics,
            &empty_device_info(),
            &payload_with_window(),
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(
            report.contains("In-process backtrace of the faulting thread (1)"),
            "{report}"
        );
        assert!(report.contains("recurse + 40"), "{report}");
        // It has to say why it exists, or a reader will assume the empty
        // MetricKit thread above it is the whole story.
        assert!(report.contains("survives a stack overflow"), "{report}");
    }

    /// Frames from the 1.52 stack overflow on Mac14,10, captured raw, so the
    /// report carries mangled names where the rule looks for demangled ones.
    #[test]
    fn report_demangles_the_in_process_backtrace() {
        let mut diagnostics = empty_diagnostics();
        diagnostics.faulting_thread_backtraces = Some(vec![
            "Backtrace of the faulting thread (innermost first):\n\
             0   Roam            0x00000001029c44ac Roam + 1033388\n\
             22  SwiftUI         0x00000001cc72e938 $s7SwiftUI12MenuBarExtraVA2A4TextVRszrlE_10isInserted7contentACyAEq_GAA18LocalizedStringKeyV_AA7BindingVySbGq_yXEtcfcq_yXEfU_Tm + 196\n\
             38  SwiftUI         0x00000001cd9c97a4 $s7SwiftUI8AppGraphC14graphDidChangeyyF + 244\n\
             39  libswiftCore.dylib 0x00000001ae283808 swift_getTypeByMangledNode + 352"
                .to_string(),
        ]);

        let report = render_metric_report(
            &diagnostics,
            &empty_device_info(),
            &payload_with_window(),
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        // The name the crash rules actually match on.
        assert!(report.contains("AppGraph.graphDidChange + 244"), "{report}");
        assert!(
            report.contains("closure #1 in MenuBarExtra<>.init + 196"),
            "{report}"
        );
        // An unmangled C symbol and the image-name fallback both survive intact.
        assert!(
            report.contains("swift_getTypeByMangledNode + 352"),
            "{report}"
        );
        assert!(report.contains("Roam + 1033388"), "{report}");
        // The raw form must be gone, or a rule's `none_of` could still see it.
        assert!(!report.contains("$s7SwiftUI"), "{report}");
    }

    #[test]
    fn demangle_backtrace_line_passes_through_what_it_cannot_parse() {
        // No address column: a header line, not a frame.
        let header = "Backtrace of the faulting thread (innermost first):";
        assert_eq!(demangle_backtrace_line(header), header);
        // A hex address with nothing after it.
        assert_eq!(
            demangle_backtrace_line("  5  Roam  0x102a3c"),
            "  5  Roam  0x102a3c"
        );
        // A non-numeric trailer is not an offset, so the whole tail is taken as
        // the symbol; that does not demangle, and the line survives unchanged.
        assert_eq!(
            demangle_backtrace_line(
                "0 Roam 0x1 $s7SwiftUI8AppGraphC14graphDidChangeyyF + notanumber"
            ),
            "0 Roam 0x1 $s7SwiftUI8AppGraphC14graphDidChangeyyF + notanumber"
        );
        // Column padding is preserved so the section stays aligned.
        assert_eq!(
            demangle_backtrace_line("  0   Roam     0x1     Roam + 8"),
            "  0   Roam     0x1     Roam + 8"
        );
    }

    #[test]
    fn report_omits_the_faulting_backtrace_section_when_there_is_none() {
        let mut diagnostics = empty_diagnostics();
        // An empty capture is not a capture - the section must not appear.
        diagnostics.faulting_thread_backtraces = Some(vec!["   \n".to_string()]);

        let report = render_metric_report(
            &diagnostics,
            &empty_device_info(),
            &payload_with_window(),
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(!report.contains("In-process backtrace"), "{report}");
    }

    #[test]
    fn report_renders_debug_errors_and_foreign_subsystems() {
        let mut diagnostics = diagnostics_with_logs(vec![LogEntry {
            subsystem: Some("com.apple.coredata".to_string()),
            ..log_entry(10, "fault", "Data", "line one\nline two")
        }]);
        diagnostics.debug_errors =
            vec!["Error Getting Log Entries: \nmissing entitlement".to_string()];

        let report = render_metric_report(
            &diagnostics,
            &empty_device_info(),
            &payload_with_window(),
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(report.contains("Debug errors (1)"), "{report}");
        assert!(report.contains("- Error Getting Log Entries:"), "{report}");
        assert!(report.contains("  missing entitlement"), "{report}");

        // A subsystem that isn't ours is worth naming.
        assert!(report.contains("[com.apple.coredata] line one"), "{report}");
        // Continuation lines indent under the message column rather than
        // restarting at column zero and reading like a new entry.
        let continuation = report
            .lines()
            .find(|line| line.trim_end().ends_with("line two"))
            .expect("continuation line");
        assert!(
            continuation.starts_with("          "),
            "continuation not indented: {continuation:?}"
        );
    }

    #[test]
    fn truncates_a_single_enormous_log_message() {
        let huge = "x".repeat(MAX_LOG_MESSAGE_CHARS + 500);
        let report = render_metric_report(
            &diagnostics_with_logs(vec![log_entry(10, "notice", "Backend", &huge)]),
            &empty_device_info(),
            &payload_with_window(),
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        assert!(report.contains("… (truncated)"), "{report}");
        assert!(!report.contains(&huge), "untruncated message in report");
    }

    #[tokio::test]
    async fn a_truncated_dyld_cache_does_not_count_as_cached() {
        let temp = tempfile::tempdir().expect("tempdir");
        let dyld = temp.path().join("dyld");
        fs::create_dir_all(&dyld).expect("dyld dir");

        // What a download killed mid-copy leaves: a base cache and subcaches
        // and nothing else. Treated as cached, it is never re-downloaded and
        // samply rejects it with "Incorrect number of SubCaches".
        fs::write(dyld.join("dyld_shared_cache_arm64e"), b"base").expect("base");
        for n in 1..=35 {
            fs::write(
                dyld.join(format!("dyld_shared_cache_arm64e.{n:02}")),
                b"sub",
            )
            .expect("sub");
        }
        assert!(
            !dyld_cache_exists(&dyld, Some("arm64e"))
                .await
                .expect("check"),
            "a cache missing its trailer files is not usable"
        );

        // The trailer `ipsw` writes last is what makes it complete.
        fs::write(dyld.join("dyld_shared_cache_arm64e.atlas"), b"atlas").expect("atlas");
        assert!(
            dyld_cache_exists(&dyld, Some("arm64e"))
                .await
                .expect("check")
        );

        // And a complete cache for another arch does not vouch for this one.
        assert!(
            !dyld_cache_exists(&dyld, Some("x86_64"))
                .await
                .expect("check")
        );
    }

    #[test]
    fn extract_ipsw_error_message_keeps_only_diagnostics() {
        let stderr =
            "⨯ failed to query ipsw.me api for buildID 25D77128 => version: build did not match";
        let stdout = "Usage:\n  ipsw download ipsw [flags]\n\nAliases:\n  ipsw, i\n";
        let summary = extract_ipsw_error_message(stderr, stdout);
        assert!(summary.starts_with("⨯ failed to query ipsw.me"));
        assert!(!summary.contains("Usage"));
    }

    /// Build a payload whose attributed thread is a single chain `depth` frames
    /// deep, the shape MetricKit emits for a runaway recursion.
    ///
    /// Assembled as text: building and serializing a `Value` that deep recurses
    /// too, so the fixture would fail before the code under test ran.
    fn deeply_nested_payload_json(depth: usize) -> String {
        const FRAME: &str = r#"{"binaryName":"Roam","binaryUUID":"4068B2EE-A54F-397E-882D-C5E3A40B789A","offsetIntoBinaryTextSegment":4096"#;

        let mut json = String::from(
            r#"{"crashDiagnostics":[{"callStackTree":{"callStacks":[{"threadAttributed":true,"callStackRootFrames":["#,
        );
        for _ in 0..depth {
            json.push_str(FRAME);
            json.push_str(r#","subFrames":["#);
        }
        // Innermost frame closes with an empty subFrames array, then every
        // enclosing frame closes its array and its object.
        json.push_str("]}".repeat(depth).as_str());
        json.push_str(r#"]}]},"diagnosticMetaData":{"signal":11}}]}"#);
        json
    }

    #[test]
    fn parses_a_stack_deeper_than_serde_jsons_default_limit() {
        // serde_json caps nesting at 128, and a stack overflow nests one level
        // per frame, so it failed with "recursion limit exceeded".
        let json = deeply_nested_payload_json(4096);

        // The default parser is why this needed fixing.
        assert!(
            serde_json::from_str::<MetricKitPayload>(&json).is_err(),
            "expected serde_json's default depth limit to reject this payload"
        );

        let payload = parse_metrickit_payload(json.as_bytes()).expect("deep payload parses");
        assert_eq!(payload.crash_diagnostics.len(), 1);

        // And every frame is reachable, not just the outermost 128.
        let uuids = payload.binary_uuids();
        assert_eq!(uuids.len(), 1);
        assert!(uuids.contains("4068B2EE-A54F-397E-882D-C5E3A40B789A"));
    }

    #[test]
    fn scanning_uuids_agrees_with_parsing_them() {
        // Ingest reads UUIDs with a flat scan, since the VM cannot map
        // `parse_metrickit_payload`'s stack. The two must not drift: the scan
        // decides which dSYMs a worker is offered.
        let real = std::fs::read(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/src/symbolicate/test-crash-payload.json"
        ))
        .expect("test payload readable");
        let parsed = parse_metrickit_payload(&real).expect("test payload parses");
        assert!(
            !parsed.binary_uuids().is_empty(),
            "test payload should carry UUIDs for this comparison to mean anything"
        );
        assert_eq!(scan_binary_uuids(&real), parsed.binary_uuids());

        // Including on the deep payloads that motivated the oversized stack:
        // the scan has no notion of depth, which is the point.
        let deep = deeply_nested_payload_json(4096);
        assert_eq!(
            scan_binary_uuids(deep.as_bytes()),
            parse_metrickit_payload(deep.as_bytes())
                .expect("deep payload parses")
                .binary_uuids()
        );
    }

    #[test]
    fn scanning_uuids_tolerates_spacing_and_rejects_non_uuids() {
        // MetricKit pretty-prints `"binaryUUID" : "..."`, but nothing promises
        // that spacing, and a value that is not a UUID must not become a dSYM
        // lookup key.
        let compact = br#"{"binaryUUID":"4068B2EE-A54F-397E-882D-C5E3A40B789A"}"#;
        let spaced = b"{\"binaryUUID\"\n  :\t \"4068B2EE-A54F-397E-882D-C5E3A40B789A\"}";
        for payload in [compact.as_slice(), spaced.as_slice()] {
            let found = scan_binary_uuids(payload);
            assert_eq!(
                found.len(),
                1,
                "failed on {:?}",
                String::from_utf8_lossy(payload)
            );
            assert!(found.contains("4068B2EE-A54F-397E-882D-C5E3A40B789A"));
        }

        assert!(scan_binary_uuids(br#"{"binaryUUID": "not-a-uuid"}"#).is_empty());
        assert!(
            scan_binary_uuids(br#"{"binaryUUIDs": ["4068B2EE-A54F-397E-882D-C5E3A40B789A"]}"#)
                .is_empty()
        );
    }

    #[test]
    fn renders_a_stack_deeper_than_the_recursion_limit() {
        // Parsing a deep stack is only half the job: rendering walked the same
        // tree recursively, so a payload deep enough to need the parser fix was
        // also deep enough to overflow the renderer.
        let payload = parse_metrickit_payload(deeply_nested_payload_json(10_000).as_bytes())
            .expect("deep payload parses");

        let report = render_metric_report(
            &empty_diagnostics(),
            &empty_device_info(),
            &payload,
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("deep report renders");

        // Frames are numbered from 0 and every one of them made it out.
        assert!(
            report.contains("0   Roam"),
            "{}",
            &report[..2000.min(report.len())]
        );
        assert!(report.contains("9999"), "deepest frame missing from report");
    }

    #[test]
    fn renders_branching_stacks_the_same_way_recursion_did() {
        // The renderer was converted from recursion to an explicit stack. The
        // contract it has to preserve: depth-first numbering, and indentation
        // that steps in only at levels that actually branch.
        let payload: MetricKitPayload = serde_json::from_value(serde_json::json!({
            "crashDiagnostics": [{
                "callStackTree": { "callStacks": [
                    { "threadAttributed": true, "callStackRootFrames": [
                        { "binaryName": "root", "binaryUUID": "4068B2EE-A54F-397E-882D-C5E3A40B789A",
                          "offsetIntoBinaryTextSegment": 0,
                          "subFrames": [
                            { "binaryName": "left", "binaryUUID": "4068B2EE-A54F-397E-882D-C5E3A40B789A",
                              "offsetIntoBinaryTextSegment": 1,
                              "subFrames": [
                                { "binaryName": "left_child", "binaryUUID": "4068B2EE-A54F-397E-882D-C5E3A40B789A",
                                  "offsetIntoBinaryTextSegment": 2 }
                              ] },
                            { "binaryName": "right", "binaryUUID": "4068B2EE-A54F-397E-882D-C5E3A40B789A",
                              "offsetIntoBinaryTextSegment": 3 }
                          ] }
                    ] }
                ] },
                "diagnosticMetaData": { "signal": 11 }
            }]
        }))
        .expect("payload deserializes");

        let report = render_metric_report(
            &empty_diagnostics(),
            &empty_device_info(),
            &payload,
            &BTreeMap::new(),
            &BTreeMap::new(),
        )
        .expect("report renders");

        let frames: Vec<&str> = report
            .lines()
            .filter(|line| {
                ["root", "left", "left_child", "right"]
                    .iter()
                    .any(|name| line.contains(name))
            })
            .collect();

        // Depth-first: a subtree is fully emitted before its parent's next
        // sibling, so left_child (2) precedes right (3).
        let order: Vec<String> = frames
            .iter()
            .map(|line| {
                line.split_whitespace()
                    .take(2)
                    .collect::<Vec<_>>()
                    .join(" ")
            })
            .collect();
        assert_eq!(
            order,
            vec!["0 root", "1 left", "2 left_child", "3 right"],
            "{report}"
        );

        // `root` has one child, so `left`/`right` do not indent past it; that
        // pair does branch, so `left_child` steps in one level.
        let indent = |name: &str| {
            frames
                .iter()
                .find(|line| line.contains(name))
                .map(|line| line.len() - line.trim_start().len())
                .expect(name)
        };
        assert_eq!(indent("root"), indent("left"), "{report}");
        assert_eq!(indent("left"), indent("right"), "{report}");
        assert!(indent("left_child") > indent("left"), "{report}");
    }

    #[test]
    fn evicts_least_recently_used_caches_over_budget() {
        let root = tempfile::tempdir().expect("tempdir");
        let system = root.path().join("system");

        // Three caches, ~4 KiB of payload each, touched oldest-first.
        let make = |device: &str, build: &str| {
            let dir = system.join(device).join(build);
            fs::create_dir_all(dir.join("dyld")).expect("mkdir");
            fs::write(
                dir.join("dyld").join("dyld_shared_cache_arm64e"),
                vec![0u8; 4096],
            )
            .expect("write cache");
            dir
        };

        let oldest = make("iPhone13,1", "23F84");
        let middle = make("iPhone15,2", "23G71");
        let newest = make("iPhone17,1", "23G71");

        for (dir, secs_ago) in [(&oldest, 3000), (&middle, 2000), (&newest, 1000)] {
            let when = std::time::SystemTime::now() - std::time::Duration::from_secs(secs_ago);
            let marker = fs::File::create(dir.join(LAST_USED_MARKER)).expect("marker");
            marker.set_modified(when).expect("set marker mtime");
        }

        // Budget fits roughly two entries, forcing exactly one eviction.
        let total = dir_size_bytes(&system);
        let budget = total - (total / 3);

        let rt = tokio::runtime::Builder::new_current_thread()
            .build()
            .expect("runtime");
        rt.block_on(enforce_system_cache_budget(&system, &newest, budget));

        assert!(
            !oldest.exists(),
            "least-recently-used cache should be evicted"
        );
        assert!(middle.exists(), "in-budget cache should survive");
        assert!(
            newest.exists(),
            "the cache just downloaded must never be evicted"
        );
    }

    #[test]
    fn never_evicts_the_cache_it_was_told_to_keep() {
        let root = tempfile::tempdir().expect("tempdir");
        let system = root.path().join("system");
        let only = system.join("iPhone17,1").join("23G71");
        fs::create_dir_all(only.join("dyld")).expect("mkdir");
        fs::write(
            only.join("dyld").join("dyld_shared_cache_arm64e"),
            vec![0u8; 8192],
        )
        .expect("write cache");

        // A budget of one byte cannot be met without dropping the kept entry.
        let rt = tokio::runtime::Builder::new_current_thread()
            .build()
            .expect("runtime");
        rt.block_on(enforce_system_cache_budget(&system, &only, 1));

        assert!(
            only.exists(),
            "eviction must not delete the cache the caller is about to use"
        );
    }

    #[test]
    fn appledb_args_carry_a_token_only_when_one_is_configured() {
        let args = appledb_args(
            "macOS",
            "MacBookAir10,1",
            "24G419",
            Path::new("/tmp/out"),
            None,
        );
        let rendered: Vec<String> = args
            .iter()
            .map(|a| a.to_string_lossy().to_string())
            .collect();

        // The macOS crash that resolved nothing was rate-limited on
        // unauthenticated GitHub API calls, so the flag has to reach ipsw.
        assert!(rendered.contains(&"--api".to_string()));
        assert_eq!(
            rendered.contains(&"--api-token".to_string()),
            appledb_api_token().is_some(),
            "token flag must track whether a token is actually configured"
        );
    }

    #[test]
    fn appledb_asks_for_an_ota_because_dyld_extraction_needs_one() {
        let args = appledb_args(
            "macOS",
            "Mac17,5",
            "25G82",
            Path::new("/tmp/out"),
            Some("arm64e"),
        );
        let rendered: Vec<String> = args
            .iter()
            .map(|a| a.to_string_lossy().to_string())
            .collect();

        // `--dyld` extracts out of an OTA zip only, and --type defaults to
        // `ipsw`. Dropping this pair is what made every appledb attempt fail
        // with "can only be extracted from OTA files".
        let type_at = rendered
            .iter()
            .position(|a| a == "--type")
            .expect("appledb must pin the firmware type");
        assert_eq!(rendered.get(type_at + 1).map(String::as_str), Some("ota"));

        // A shipped build must not ask for the beta catalog.
        assert!(!rendered.contains(&"--beta".to_string()));
    }

    #[test]
    fn seed_builds_never_ask_for_the_beta_catalog() {
        // ipsw rejects `--beta` alongside `--build`, and every lookup here is
        // by exact build, so emitting it would fail the call.
        for rendered in [
            appledb_args("macOS", "Mac15,9", "26A5406e", Path::new("/tmp/out"), None),
            ota_args("macos", "Mac15,9", "26A5406e", Path::new("/tmp/out"), None),
            ipsw_me_args("Mac15,9", "26A5406e", Path::new("/tmp/out"), None),
        ]
        .map(|args| {
            args.iter()
                .map(|a| a.to_string_lossy().to_string())
                .collect::<Vec<_>>()
        }) {
            assert!(
                !rendered.contains(&"--beta".to_string()),
                "--beta is incompatible with --build: {rendered:?}"
            );
            assert!(rendered.contains(&"--build".to_string()));
        }
    }

    #[test]
    fn ota_args_carry_platform_build_and_arch() {
        let args = ota_args(
            "macos",
            "Mac17,5",
            "25G82",
            Path::new("/tmp/out"),
            Some("arm64e"),
        );
        let rendered: Vec<String> = args
            .iter()
            .map(|a| a.to_string_lossy().to_string())
            .collect();

        assert_eq!(rendered[0], "download");
        assert_eq!(rendered[1], "ota");
        for (flag, value) in [
            ("--platform", "macos"),
            ("--device", "Mac17,5"),
            ("--build", "25G82"),
            // appledb has no --dyld-arch; this subcommand does.
            ("--dyld-arch", "arm64e"),
        ] {
            let at = rendered
                .iter()
                .position(|a| a == flag)
                .unwrap_or_else(|| panic!("{flag} missing from {rendered:?}"));
            assert_eq!(rendered.get(at + 1).map(String::as_str), Some(value));
        }
        assert!(rendered.contains(&"--dyld".to_string()));
    }

    #[test]
    fn ota_platforms_follow_the_catalog_not_the_marketing_name() {
        // iPadOS and iPodOS ship as part of the ios OTA platform.
        assert_eq!(ota_platform("iOS"), Some("ios"));
        assert_eq!(ota_platform("iPadOS"), Some("ios"));
        assert_eq!(ota_platform("iPodOS"), Some("ios"));
        assert_eq!(ota_platform("macOS"), Some("macos"));
        assert_eq!(ota_platform("watchOS"), Some("watchos"));
        assert_eq!(ota_platform("tvOS"), Some("tvos"));
        assert_eq!(ota_platform("audioOS"), Some("audioos"));

        // bridgeOS has no OTA platform, so the source is skipped rather than
        // invoked with a flag value ipsw rejects.
        assert_eq!(ota_platform("bridgeOS"), None);

        // Every family parse_os_family can emit must be handled or explicitly
        // skipped, so a new one cannot silently mean "skip".
        for family in [
            "iOS", "iPadOS", "iPodOS", "macOS", "watchOS", "tvOS", "audioOS",
        ] {
            assert!(
                ota_platform(family).is_some(),
                "{family} resolves an OS family but no OTA platform"
            );
        }
    }

    /// End to end against a real cache: `ROAM_SYMBOLICATION_ROOT` holds
    /// `system/iPhone14,3/24B156/dyld` from the symbolicator and
    /// `ROAM_PAYLOAD` is the raw diagnostics.json from thread
    /// 1573889376075653131, the 1.63 keyboard entry deadlock.
    #[tokio::test]
    #[ignore]
    async fn names_private_frames_of_a_real_keyboard_deadlock_report() {
        let root = PathBuf::from(std::env::var("ROAM_SYMBOLICATION_ROOT").unwrap());
        let payloads: Vec<String> =
            serde_json::from_slice(&std::fs::read(std::env::var("ROAM_PAYLOAD").unwrap()).unwrap())
                .unwrap();
        let scratch = tempfile::tempdir().unwrap();
        let payload_path = scratch.path().join("metric.json");
        std::fs::write(&payload_path, &payloads[0]).unwrap();

        let client = SymbolicationClient::new(root);
        let report_path = client
            .symbolicate_diagnostics(&empty_diagnostics(), &empty_device_info(), &payload_path)
            .await
            .unwrap();
        let report = std::fs::read_to_string(report_path).unwrap();
        for name in [
            "-[UIResponder(UIResponderInputViewAdditions) inputDashboardViewController]",
            "-[UISystemInputAssistantViewController _customCenterViewController:]",
            "updateSDFShapeViewAsync",
            "SDFLayer.beginUpdatingStyle",
        ] {
            assert!(report.contains(name), "missing {name}:\n{report}");
        }
        // Inside a function the cache names only by its start.
        assert!(report.contains("fun_840438"), "{report}");
    }

    #[tokio::test]
    async fn an_empty_download_directory_does_not_count_as_a_cache() {
        // The regression that cost three payloads: `ipsw` exits 0 having
        // written nothing, and treating that as success published no-symbol
        // reports and reaped the payloads that would otherwise have retried.
        let dir = tempfile::tempdir().expect("tempdir");
        assert!(
            !dyld_cache_exists(dir.path(), Some("arm64e"))
                .await
                .expect("empty dir is readable"),
            "an empty directory must not read as a downloaded cache"
        );
    }

    #[test]
    fn converts_macho_uuid_to_breakpad_id() {
        assert_eq!(
            binary_uuid_to_breakpad_id("4068B2EE-A54F-397E-882D-C5E3A40B789A").as_deref(),
            Some("4068B2EEA54F397E882DC5E3A40B789A0")
        );
        assert_eq!(
            binary_uuid_to_breakpad_id("00000000-0000-0000-0000-000000000000"),
            None
        );
    }

    #[test]
    fn infers_common_dyld_cache_paths_from_binary_name() {
        let paths = likely_dylib_paths(&LibraryInfo {
            name: Some("CoreFoundation".to_string()),
            ..Default::default()
        });

        assert!(paths.contains(
            &"/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation".to_string()
        ));
        assert!(
            paths.contains(
                &"/System/Library/PrivateFrameworks/CoreFoundation.framework/CoreFoundation"
                    .to_string()
            )
        );
        assert!(paths.contains(&"/usr/lib/CoreFoundation.dylib".to_string()));
    }

    // backend/testing-support/dSYMs/Roam.app.debug.dSYM pairs the stripped
    // Roam binary with a fat Roam.debug.dylib holding most Swift symbols.
    // UUIDs verified with `dwarfdump --uuid`.
    const ROAM_DEBUG_BINARY_BREAKPAD_ID: &str = "C634B9DAA08E3551A316BA831333CDCA0";
    const ROAM_DEBUG_DYLIB_BREAKPAD_ID: &str = "F2DD80141670331C87EBC34428FBB75D0";
    const ROAM_DEBUG_DYLIB_UUID: &str = "F2DD8014-1670-331C-87EB-C34428FBB75D";

    fn testing_support_dir() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testing-support")
    }

    fn zip_directory_to_bytes(root: &Path) -> Vec<u8> {
        let mut buffer = Vec::new();
        let cursor = Cursor::new(&mut buffer);
        let mut writer = zip::ZipWriter::new(cursor);
        let options = zip::write::SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Stored);
        let parent = root.parent().expect("root must have parent");
        write_dir_entries(&mut writer, options, parent, root);
        writer.finish().expect("finalize zip");
        buffer
    }

    fn write_dir_entries<W: std::io::Write + std::io::Seek>(
        writer: &mut zip::ZipWriter<W>,
        options: zip::write::SimpleFileOptions,
        base: &Path,
        path: &Path,
    ) {
        for entry in fs::read_dir(path).expect("read_dir") {
            let entry = entry.expect("dir entry");
            let path = entry.path();
            // Skip macOS Finder metadata so it doesn't appear in the archive.
            if path.file_name().and_then(|n| n.to_str()) == Some(".DS_Store") {
                continue;
            }
            let rel = path
                .strip_prefix(base)
                .expect("path under base")
                .to_string_lossy()
                .into_owned();
            if path.is_dir() {
                writer.add_directory(&rel, options).expect("add_directory");
                write_dir_entries(writer, options, base, &path);
            } else {
                writer.start_file(&rel, options).expect("start_file");
                let bytes = fs::read(&path).expect("read file");
                std::io::Write::write_all(writer, &bytes).expect("write file");
            }
        }
    }

    fn empty_diagnostics() -> RoamDebugInfo {
        RoamDebugInfo {
            installation_info: empty_device_info(),
            user_defaults: Default::default(),
            space_on_device: None,
            devices: vec![],
            app_links: vec![],
            interfaces: vec![],
            logs: vec![],
            debug_errors: vec![],
            language: super::super::diagnostics::DebugLanguage {
                device_language_code: "en".to_string(),
                translated_language_code: "en".to_string(),
            },
            faulting_thread_backtraces: None,
        }
    }

    fn empty_device_info() -> crate::database::DeviceInfo {
        crate::database::DeviceInfo {
            user_id: None,
            build_version: None,
            release_version: None,
            os_platform: None,
            os_version: None,
            user_locale: None,
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn store_dsym_zip_indexes_uuids_from_debug_dsym() {
        let symbolication_root = tempfile::tempdir().expect("tempdir");
        let client = SymbolicationClient::new(symbolication_root.path().to_path_buf());

        let debug_dsym = testing_support_dir()
            .join("dSYMs")
            .join("Roam.app.debug.dSYM");
        assert!(
            debug_dsym.is_dir(),
            "fixture missing: {}",
            debug_dsym.display()
        );

        let zipped = zip_directory_to_bytes(&debug_dsym);
        let stored = client
            .store_dsym_zip_with_metadata(None, zipped)
            .await
            .expect("store .debug dSYM zip");

        // Both UUIDs in the .debug bundle must be indexed, or the payload's
        // "Roam.debug.dylib" frames come back unresolved.
        assert!(
            stored
                .indexed_debug_ids
                .contains(&ROAM_DEBUG_BINARY_BREAKPAD_ID.to_string()),
            "missing Roam binary UUID in indexed list {:?}",
            stored.indexed_debug_ids
        );
        assert!(
            stored
                .indexed_debug_ids
                .contains(&ROAM_DEBUG_DYLIB_BREAKPAD_ID.to_string()),
            "missing Roam.debug.dylib UUID in indexed list {:?}",
            stored.indexed_debug_ids
        );

        // Both expected paths must be reachable through the by-debug-id and
        // by-uuid caches that get_candidate_paths_for_debug_file consults.
        for breakpad_id in [ROAM_DEBUG_BINARY_BREAKPAD_ID, ROAM_DEBUG_DYLIB_BREAKPAD_ID] {
            let by_debug_id = symbolication_root
                .path()
                .join("cache")
                .join("by-debug-id")
                .join(breakpad_id);
            assert!(
                by_debug_id.exists(),
                "by-debug-id symlink missing: {}",
                by_debug_id.display()
            );
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn symbolicate_diagnostics_resolves_indexed_debug_dylib() {
        let symbolication_root = tempfile::tempdir().expect("tempdir");
        let client = SymbolicationClient::new(symbolication_root.path().to_path_buf());

        let debug_dsym = testing_support_dir()
            .join("dSYMs")
            .join("Roam.app.debug.dSYM");
        let zipped = zip_directory_to_bytes(&debug_dsym);
        client
            .store_dsym_zip_with_metadata(None, zipped)
            .await
            .expect("store .debug dSYM");

        // Synthetic payload referencing a UUID we just indexed. The offset is
        // arbitrary and may not resolve, but the binary must be locatable.
        let payload = serde_json::json!({
            "timeStampBegin": "2026-05-04 08:30:00",
            "timeStampEnd": "2026-05-04 08:30:00",
            "crashDiagnostics": [{
                "version": "1.0.0",
                "callStackTree": {
                    "callStacks": [{
                        "threadAttributed": true,
                        "callStackRootFrames": [{
                            "binaryUUID": ROAM_DEBUG_DYLIB_UUID,
                            "binaryName": "Roam.debug.dylib",
                            "offsetIntoBinaryTextSegment": 0x69B454u64,
                            "sampleCount": 1,
                            "subFrames": []
                        }],
                    }],
                    "callStackPerThread": true
                },
                "diagnosticMetaData": {
                    "platformArchitecture": "arm64e",
                    "bundleIdentifier": "com.msdrigg.roam",
                }
            }]
        });

        let payload_dir = symbolication_root.path().join("payload");
        std::fs::create_dir_all(&payload_dir).unwrap();
        let payload_path = payload_dir.join("metric.json");
        tokio::fs::write(&payload_path, serde_json::to_vec(&payload).unwrap())
            .await
            .unwrap();

        let report_path = client
            .symbolicate_diagnostics(&empty_diagnostics(), &empty_device_info(), &payload_path)
            .await
            .expect("symbolicate_diagnostics succeeded");
        let report = tokio::fs::read_to_string(&report_path).await.unwrap();

        // The user's bug: every frame came back as "(unresolved ...)" because
        // the .debug dSYM had not been uploaded. With the dSYM indexed, the
        // looked-up binary's UUID must not appear in the unresolved section.
        assert!(
            !report.contains("Unresolved UUIDs"),
            "expected no unresolved-UUIDs section, got report:\n{report}"
        );
        let unresolved_marker = format!("(unresolved {ROAM_DEBUG_DYLIB_UUID}");
        assert!(
            !report.contains(&unresolved_marker),
            "frame still unresolved for {ROAM_DEBUG_DYLIB_UUID}; report:\n{report}"
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn symbolicate_diagnostics_resolves_production_payload_with_matching_dsym() {
        // Roam.debug.dylib in mkmetrickit-upload.json has UUID
        // 7FF52BDA-EDB7-3091-827E-A6F67F3BA16C, whose dSYM is under
        // testing-support/dSYMs. Its frames must resolve; the system
        // frameworks stay unresolved since no dyld cache is fetched here.
        let symbolication_root = tempfile::tempdir().expect("tempdir");
        let client = SymbolicationClient::new(symbolication_root.path().to_path_buf());

        let dylib_dsym = testing_support_dir()
            .join("dSYMs")
            .join("Roam.debug.dylib.dSYM");
        assert!(
            dylib_dsym.is_dir(),
            "fixture missing: {}",
            dylib_dsym.display()
        );
        let zipped = zip_directory_to_bytes(&dylib_dsym);
        let stored = client
            .store_dsym_zip_with_metadata(None, zipped)
            .await
            .expect("store Roam.debug.dylib.dSYM");
        let upload_dylib_breakpad = "7FF52BDAEDB73091827EA6F67F3BA16C0";
        assert!(
            stored
                .indexed_debug_ids
                .contains(&upload_dylib_breakpad.to_string()),
            "expected production-payload UUID to be indexed; got {:?}",
            stored.indexed_debug_ids
        );

        // Real upload payload format: outer JSON is a Vec<String>, where
        // each string is itself a MetricKit JSON document.
        let upload_path = testing_support_dir().join("mkmetrickit-upload.json");
        let payloads: Vec<String> =
            serde_json::from_slice(&std::fs::read(&upload_path).expect("read upload"))
                .expect("parse upload outer array");
        let mut payload: serde_json::Value =
            serde_json::from_str(&payloads[0]).expect("parse upload payload JSON");

        // Strip osVersion/deviceType so ensure_system_symbols_cached won't
        // shell out to `ipsw` to download a dyld_shared_cache (which can
        // take minutes and shouldn't run in unit tests).
        if let Some(diagnostics) = payload
            .get_mut("crashDiagnostics")
            .and_then(|v| v.as_array_mut())
        {
            for diag in diagnostics {
                if let Some(meta) = diag
                    .get_mut("diagnosticMetaData")
                    .and_then(|v| v.as_object_mut())
                {
                    meta.remove("osVersion");
                    meta.remove("deviceType");
                }
            }
        }

        let payload_dir = symbolication_root.path().join("payload");
        std::fs::create_dir_all(&payload_dir).unwrap();
        let payload_path = payload_dir.join("metric.json");
        tokio::fs::write(&payload_path, serde_json::to_vec(&payload).unwrap())
            .await
            .unwrap();

        let report_path = client
            .symbolicate_diagnostics(&empty_diagnostics(), &empty_device_info(), &payload_path)
            .await
            .expect("symbolicate_diagnostics");
        let report = tokio::fs::read_to_string(&report_path).await.unwrap();

        // Roam.debug.dylib must no longer appear in the unresolved bucket
        // and no per-frame "(unresolved 7FF52BDA…)" marker may remain.
        let upload_dylib_uuid = "7FF52BDA-EDB7-3091-827E-A6F67F3BA16C";
        let unresolved_marker = format!("(unresolved {upload_dylib_uuid}");
        assert!(
            !report.contains(&unresolved_marker),
            "expected {upload_dylib_uuid} frames to resolve, but report contains \
             {unresolved_marker:?}; report:\n{report}"
        );
        // System framework UUIDs (SwiftUI, AppKit, …) remain unindexed in
        // this test, so the report should still have an Unresolved section
        // - but it must not list the dylib UUID we just indexed.
        if let Some(unresolved_section) = report.split_once("Unresolved UUIDs") {
            let after = unresolved_section.1;
            let next_section_end = after.find("\n\n").unwrap_or(after.len());
            let unresolved_block = &after[..next_section_end];
            assert!(
                !unresolved_block.contains(upload_dylib_uuid),
                "indexed {upload_dylib_uuid} should not be listed as unresolved; section:\n{unresolved_block}"
            );
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn symbolicate_diagnostics_marks_uuids_unresolved_when_dsym_missing() {
        // Reproduces the original failure: when no dSYM is indexed for a
        // referenced binary, the report must surface that UUID under
        // "Unresolved UUIDs" instead of erroring out or silently dropping it.
        // diagnosticMetaData intentionally omits osVersion so this test does
        // not trigger ensure_system_symbols_cached (which shells out to
        // `ipsw` and is not appropriate for unit tests).
        let symbolication_root = tempfile::tempdir().expect("tempdir");
        let client = SymbolicationClient::new(symbolication_root.path().to_path_buf());

        // UUID from the real production upload that motivated this fixture -
        // the build's Roam.debug.dylib was never uploaded, so symbolication
        // returned every frame for it as "(unresolved ...)".
        let missing_uuid = "7FF52BDA-EDB7-3091-827E-A6F67F3BA16C";
        let payload = serde_json::json!({
            "timeStampBegin": "2026-05-04 08:30:00",
            "timeStampEnd": "2026-05-04 08:30:00",
            "crashDiagnostics": [{
                "version": "1.0.0",
                "callStackTree": {
                    "callStacks": [{
                        "threadAttributed": true,
                        "callStackRootFrames": [{
                            "binaryUUID": missing_uuid,
                            "binaryName": "Roam.debug.dylib",
                            "offsetIntoBinaryTextSegment": 178116u64,
                            "sampleCount": 1,
                            "subFrames": []
                        }],
                    }],
                    "callStackPerThread": true
                },
                "diagnosticMetaData": {
                    "bundleIdentifier": "com.msdrigg.roam"
                }
            }]
        });

        let payload_dir = symbolication_root.path().join("payload");
        std::fs::create_dir_all(&payload_dir).unwrap();
        let payload_path = payload_dir.join("metric.json");
        tokio::fs::write(&payload_path, serde_json::to_vec(&payload).unwrap())
            .await
            .unwrap();

        let report_path = client
            .symbolicate_diagnostics(&empty_diagnostics(), &empty_device_info(), &payload_path)
            .await
            .expect("symbolicate_diagnostics");
        let report = tokio::fs::read_to_string(&report_path).await.unwrap();

        assert!(
            report.contains("Unresolved UUIDs"),
            "expected an Unresolved UUIDs section in report:\n{report}"
        );
        assert!(
            report.contains(missing_uuid),
            "expected unresolved UUID {missing_uuid} in report:\n{report}"
        );
    }
}
