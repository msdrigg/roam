use crate::database::DeviceInfo;
use crate::symbolicate::RoamDebugInfo;
use anyhow::{Context, Result};
use object::read::macho::{FatArch, MachOFatFile32, MachOFatFile64};
use object::{FileKind, Object};
use samply_symbols::debugid::DebugId;
use samply_symbols::{
    CandidatePathInfo, FileAndPathHelper, FileAndPathHelperResult, FileLocation, FrameDebugInfo,
    FramesLookupResult, LibraryInfo, LookupAddress, OptionallySendFuture, SymbolManager,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fmt::{Display, Write as _};
use std::fs::{self, File};
use std::io::Cursor;
use std::path::{Path, PathBuf};
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
        if !dylib_paths.is_empty() {
            for dyld_cache_path in self.get_dyld_shared_cache_paths(library_info.arch.as_deref())? {
                for dylib_path in &dylib_paths {
                    options.push(CandidatePathInfo::InDyldCache {
                        dyld_cache_path: dyld_cache_path.clone(),
                        dylib_path: dylib_path.clone(),
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
            Self::store_dsym_zip_blocking(symbolication_root, metadata, dsym_zip)
        })
        .await
        .context("joining dSYM zip extraction task")?
    }

    fn store_dsym_zip_blocking(
        symbolication_root: PathBuf,
        metadata: Option<DsymUploadMetadata>,
        dsym_zip: Vec<u8>,
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

        extract_zip_archive(&dsym_zip, &extracted_root)?;

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
        if dyld_cache_exists(&dyld_dir, requirement.arch.as_deref()).await? {
            tracing::info!(
                device_type = %requirement.device_type,
                build_id = %requirement.build_id,
                arch = requirement.arch.as_deref().unwrap_or("--"),
                "System dyld_shared_cache already cached"
            );
            return Ok(());
        }

        tracing::info!(
            device_type = %requirement.device_type,
            build_id = %requirement.build_id,
            arch = requirement.arch.as_deref().unwrap_or("--"),
            os_family = requirement.os_family.as_deref().unwrap_or("--"),
            "Downloading system dyld_shared_cache via ipsw"
        );

        tokio::fs::create_dir_all(&dyld_dir)
            .await
            .with_context(|| format!("creating dyld cache directory {}", dyld_dir.display()))?;

        let started = std::time::Instant::now();
        extract_dyld_shared_cache(
            &requirement.device_type,
            &requirement.build_id,
            &dyld_dir,
            requirement.arch.as_deref(),
            requirement.os_family.as_deref(),
        )
        .await?;
        normalize_dyld_dir(&dyld_dir);
        tracing::info!(
            device_type = %requirement.device_type,
            build_id = %requirement.build_id,
            elapsed_ms = started.elapsed().as_millis() as u64,
            "Downloaded system dyld_shared_cache"
        );
        Ok(())
    }
}

impl SymbolicationClient {
    fn collect_symbolication_requests(
        frame: &MetricKitCallStackFrame,
        requests: &mut BTreeMap<String, SymbolicationRequest>,
    ) {
        if let (Some(binary_uuid), Some(offset)) = (
            frame.binary_uuid.as_deref(),
            frame.offset_into_binary_text_segment,
        ) {
            if let Some(breakpad_id) = binary_uuid_to_breakpad_id(binary_uuid) {
                if let Ok(offset) = u32::try_from(offset) {
                    requests
                        .entry(breakpad_id)
                        .or_default()
                        .add(offset, frame.binary_name.as_deref());
                }
            }
        }

        for sub_frame in &frame.sub_frames {
            Self::collect_symbolication_requests(sub_frame, requests);
        }
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
        let payload: MetricKitPayload = serde_json::from_slice(&payload_bytes)
            .with_context(|| format!("parsing MetricKit payload {}", metrics_payload.display()))?;
        tracing::info!(
            payload_bytes = payload_bytes.len(),
            crash_diagnostics = payload.crash_diagnostics.len(),
            "Parsed MetricKit payload"
        );

        if let Err(error) = self.ensure_system_symbols_cached(&payload).await {
            tracing::warn!(?error, "Could not prepare IPSW/dyld shared cache symbols");
        }

        let mut requests = BTreeMap::new();
        for crash in &payload.crash_diagnostics {
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
            match self
                .symbolicate_requested_addresses_for_lib(&breakpad_id, request, &symbol_manager)
                .await
            {
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
                    symbolicated_addresses.insert(breakpad_id, result);
                }
                Err(err) => {
                    tracing::warn!(%breakpad_id, error = ?err, "Could not symbolicate binary UUID");
                    lookup_errors.insert(breakpad_id, err.to_string());
                }
            }
        }

        let report = render_metric_report(
            diagnostics,
            installation_info,
            &payload,
            &symbolicated_addresses,
            &lookup_errors,
        )?;
        tokio::fs::write(&report_path, &report)
            .await
            .with_context(|| format!("writing symbolicated report {}", report_path.display()))?;
        tracing::info!(
            report = %report_path.display(),
            report_bytes = report.len(),
            resolved_binaries = symbolicated_addresses.len(),
            unresolved_binaries = lookup_errors.len(),
            elapsed_ms = started.elapsed().as_millis() as u64,
            "Wrote symbolicated report"
        );
        Ok(report_path)
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
}

impl MetricKitPayload {
    /// Walk every call-stack frame and collect the binary UUIDs referenced.
    /// Used by the upload handler to record which dSYMs the symbolicator will
    /// need before the row gets handed to a worker.
    pub(crate) fn binary_uuids(&self) -> BTreeSet<String> {
        let mut out = BTreeSet::new();
        for crash in &self.crash_diagnostics {
            for stack in &crash.call_stack_tree.call_stacks {
                for frame in &stack.call_stack_root_frames {
                    collect_binary_uuids(frame, &mut out);
                }
            }
        }
        out
    }
}

fn collect_binary_uuids(frame: &MetricKitCallStackFrame, out: &mut BTreeSet<String>) {
    if let Some(uuid) = frame.binary_uuid.as_deref() {
        if let Ok(parsed) = Uuid::parse_str(uuid) {
            if !parsed.is_nil() {
                out.insert(parsed.to_string().to_ascii_uppercase());
            }
        }
    }
    for sub in &frame.sub_frames {
        collect_binary_uuids(sub, out);
    }
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

#[derive(Debug)]
struct SystemSymbolRequirement {
    device_type: String,
    build_id: String,
    arch: Option<String>,
    os_family: Option<String>,
}

impl MetricKitPayload {
    fn system_symbol_requirement(&self) -> Option<SystemSymbolRequirement> {
        self.crash_diagnostics
            .iter()
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

async fn extract_dyld_shared_cache(
    device_type: &str,
    build_id: &str,
    output_dir: &Path,
    arch: Option<&str>,
    os_family: Option<&str>,
) -> Result<()> {
    let mut failures: Vec<String> = Vec::new();

    // ipsw.me is the fastest source but lags for very new builds and doesn't
    // index Rapid Security Response variants separately. Try it first.
    match run_ipsw_dyld_download(
        "ipsw.me",
        ipsw_me_args(device_type, build_id, output_dir, arch),
    )
    .await
    {
        Ok(()) => return Ok(()),
        Err(e) => failures.push(format!("ipsw.me: {e:#}")),
    }

    // appledb has a broader catalog (community-maintained), often picks up
    // newer builds before ipsw.me does. Requires the OS family.
    if let Some(os) = os_family {
        match run_ipsw_dyld_download(
            "appledb",
            appledb_args(os, device_type, build_id, output_dir, arch),
        )
        .await
        {
            Ok(()) => return Ok(()),
            Err(e) => failures.push(format!("appledb: {e:#}")),
        }
    } else {
        failures.push("appledb: skipped (no osVersion family in payload)".to_string());
    }

    anyhow::bail!(
        "no dyld_shared_cache source had build {build_id} for {device_type} ({})",
        failures.join("; ")
    );
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
    // --api forces use of the GitHub API instead of a full local clone of
    // appledb (~250 MB). The clone often hangs the first run on stateless
    // containers; the API path is a few HTTP calls.
    vec![
        "download".into(),
        "appledb".into(),
        "--api".into(),
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
    ]
}

/// Upper bound for any single ipsw download attempt. Real macOS dyld
/// caches embedded in IPSWs are several GB, so this is generous,
/// but bounded so a hung subprocess can't pin the worker forever.
const IPSW_DOWNLOAD_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(8 * 60 * 60);

async fn run_ipsw_dyld_download(label: &str, args: Vec<std::ffi::OsString>) -> Result<()> {
    use portable_pty::{native_pty_system, CommandBuilder, PtySize};
    use std::io::Read;

    tracing::info!(strategy = label, "Trying ipsw dyld download");
    let started = std::time::Instant::now();

    tracing::info!(
        "Running ipsw with args: {:?}",
        args.iter().map(|s| s.to_string_lossy()).collect::<Vec<_>>()
    );

    // ipsw uses the `mpb` Go progress bar library, which checks `isatty` on its
    // output and renders nothing when the fd isn't a terminal. Without a pty we
    // get the bullet log lines but no download progress at all. Allocate a pty
    // so ipsw believes it's on a terminal, then read its master end like any
    // other pipe.
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
/// handle other escape forms (OSC, charset selection, etc.) — mpb only emits CSI.
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

async fn dyld_cache_exists(dyld_dir: &Path, arch: Option<&str>) -> Result<bool> {
    normalize_dyld_dir(dyld_dir);

    let Ok(mut entries) = tokio::fs::read_dir(dyld_dir).await else {
        return Ok(false);
    };

    while let Some(entry) = entries.next_entry().await? {
        let filename = entry.file_name().to_string_lossy().to_string();
        if filename.starts_with("dyld_shared_cache")
            && arch.is_none_or(|arch| filename.contains(arch))
        {
            return Ok(true);
        }
    }
    Ok(false)
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

fn parse_os_build_id(os_version: &str) -> Option<String> {
    let start = os_version.rfind('(')? + 1;
    let end = os_version[start..].find(')')? + start;
    Some(os_version[start..end].to_string())
}

fn parse_os_family(os_version: &str) -> Option<String> {
    let candidate = os_version.split_whitespace().next()?.to_string();
    if candidate.is_empty() {
        None
    } else {
        Some(candidate)
    }
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
    } else {
        paths.insert(format!(
            "/System/Library/Frameworks/{name}.framework/{name}"
        ));
        paths.insert(format!(
            "/System/Library/PrivateFrameworks/{name}.framework/{name}"
        ));
        paths.insert(format!("/usr/lib/{name}.dylib"));
        paths.insert(format!("/usr/lib/system/{name}.dylib"));
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
        writeln!(report, "Unresolved UUIDs")?;
        for (breakpad_id, error) in lookup_errors {
            writeln!(report, "- {breakpad_id}: {error}")?;
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

        if !crash.diagnostic_meta_data.is_empty() {
            writeln!(report, "Metadata:")?;
            for (key, value) in &crash.diagnostic_meta_data {
                writeln!(report, "  {key}: {}", render_json_scalar(value))?;
            }
        }

        for (stack_index, call_stack) in crash.call_stack_tree.call_stacks.iter().enumerate() {
            writeln!(
                report,
                "Thread {}{}:",
                stack_index,
                if call_stack.thread_attributed {
                    " (attributed)"
                } else {
                    ""
                }
            )?;
            for frame in &call_stack.call_stack_root_frames {
                render_frame(&mut report, frame, 1, symbolicated_addresses, lookup_errors)?;
            }
            writeln!(report)?;
        }
    }

    Ok(report)
}

fn render_frame(
    report: &mut String,
    frame: &MetricKitCallStackFrame,
    depth: usize,
    symbolicated_addresses: &BTreeMap<String, LookedUpAddresses>,
    lookup_errors: &BTreeMap<String, String>,
) -> Result<()> {
    let indent = "  ".repeat(depth);
    let binary_name = frame.binary_name.as_deref().unwrap_or("<unknown>");
    let offset = frame.offset_into_binary_text_segment;
    let symbol = frame_symbol(frame, symbolicated_addresses, lookup_errors);
    let sample_count = frame
        .sample_count
        .map(|count| format!(" samples={count}"))
        .unwrap_or_default();

    writeln!(
        report,
        "{indent}{binary_name} {} {}{}",
        offset
            .map(|offset| format!("+0x{offset:x}"))
            .unwrap_or_else(|| "+?".to_string()),
        symbol,
        sample_count
    )?;

    for sub_frame in &frame.sub_frames {
        render_frame(
            report,
            sub_frame,
            depth + 1,
            symbolicated_addresses,
            lookup_errors,
        )?;
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
            if let Some(frames) = &result.inline_frames {
                if let Some(frame) = frames.first() {
                    if let Some(location) = render_debug_frame_location(frame) {
                        symbol.push_str(" at ");
                        symbol.push_str(&location);
                    }
                }
            }
            return symbol;
        }
        return format!("(no symbol for {binary_uuid} +0x{offset:x})");
    }

    if let Some(error) = lookup_errors.get(&breakpad_id) {
        return format!("(unresolved {binary_uuid}: {error})");
    }

    format!("(unresolved {binary_uuid})")
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

fn extract_zip_archive(dsym_zip: &[u8], extracted_root: &Path) -> Result<()> {
    let reader = Cursor::new(dsym_zip);
    let mut archive = zip::ZipArchive::new(reader).context("opening dSYM zip archive")?;
    for index in 0..archive.len() {
        let mut file = archive
            .by_index(index)
            .with_context(|| format!("reading zip entry {index}"))?;
        let Some(enclosed_name) = file.enclosed_name() else {
            tracing::warn!(entry = file.name(), "Skipping unsafe zip entry path");
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

fn find_dwarf_files_impl(
    path: &Path,
    result: &mut Vec<PathBuf>,
    inside_dsym: bool,
) -> Result<()> {
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
        // A `.dSYM` directory should not legitimately contain another `.dSYM`.
        // Skip nested ones — they're typically build-tool detritus, and walking
        // into them feeds non-Mach-O files (Info.plist, etc.) to the UUID
        // reader, which then fails the whole upload.
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
        assert!(paths.contains(
            &"/System/Library/PrivateFrameworks/CoreFoundation.framework/CoreFoundation"
                .to_string()
        ));
        assert!(paths.contains(&"/usr/lib/CoreFoundation.dylib".to_string()));
    }

    // The .debug dSYM lives under backend/testing-support/dSYMs/Roam.app.debug.dSYM.
    // It pairs the stripped Roam binary with a fat Roam.debug.dylib that holds
    // the bulk of the Swift symbols, and was the one missing from the upload
    // when symbolication of the production payload returned every frame as
    // "(unresolved ...)". UUIDs verified with `dwarfdump --uuid`.
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

        // Both UUIDs in the .debug bundle must be indexed; if either is
        // missing, the production crash payload's "Roam.debug.dylib" frames
        // come back as "(unresolved ...)" — the failure mode that motivated
        // this fixture in the first place.
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

        // Synthetic MetricKit payload referencing a UUID we just indexed.
        // Offset is arbitrary; symbol resolution at this exact offset isn't
        // guaranteed (samply may report "no symbol for ..."), but the binary
        // must still be locatable — which is what this regression guards.
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
        // The Roam.debug.dylib in the production mkmetrickit-upload.json
        // payload has UUID 7FF52BDA-EDB7-3091-827E-A6F67F3BA16C. The dSYM
        // for that exact UUID lives at testing-support/dSYMs/Roam.debug.dylib.dSYM.
        // With it indexed, the upload's frames for that binary must come
        // back resolved (not "(unresolved ...)") — even though the rest of
        // the system frameworks in the payload remain unresolved because we
        // don't fetch dyld_shared_cache here.
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
        // write to ./symbolication-test-report.txt so we can inspect the full report if assertions fail.
        // tokio::fs::write("symbolication-test-report.txt", &report)
        //     .await
        //     .expect("write report for inspection");

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
        // — but it must not list the dylib UUID we just indexed.
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

        // UUID from the real production upload that motivated this fixture —
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
