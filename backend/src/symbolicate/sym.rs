use crate::database::DeviceInfo;
use crate::symbolicate::{ApplePlatformVersion, RoamDebugInfo};
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
use tokio::process::Command;
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

    fn device_dir(&self, device_uuid: Uuid) -> PathBuf {
        self.symbolication_root.join(device_uuid.to_string())
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
        // Dyld shared caches are only loaded from local files.
        let mut filename = self.path.file_name().unwrap().to_owned();
        filename.push(suffix);
        Some(self.with_path(self.path.with_file_name(filename)))
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
                        add_entries_in_dir(build.path().join("dyld"));
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
    pub symbol_address: u32,
    pub symbol_name: String,
    pub function_size: Option<u32>,
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

    pub fn add_address_symbol(
        &mut self,
        address: u32,
        symbol_address: u32,
        symbol_name: String,
        function_size: Option<u32>,
    ) {
        *self.address_results.get_mut(&address).unwrap() = Some(AddressResult {
            symbol_address,
            symbol_name,
            function_size,
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
                    symbol_address: address, // TODO: Would be nice to get the actual function start address from addr2line
                    symbol_name: outer_function_name
                        .map_or_else(|| format!("0x{address:x}"), str::to_string),
                    function_size: None,
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
                symbolication_result.add_address_symbol(
                    address,
                    address_info.symbol.address,
                    address_info.symbol.name,
                    address_info.symbol.size,
                );
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
    // Placeholder methods that you would implement based on your storage
    fn device_dsym_dir(&self, device_uuid: &str) -> PathBuf {
        self.symbolication_root
            .join("device-roots")
            .join(device_uuid)
    }

    fn binary_dsym_path(
        &self,
        build_version: &str,
        bundle_identifier: &str,
        os_platform: &ApplePlatformVersion,
    ) -> PathBuf {
        self.symbolication_root
            .join("binaries")
            .join(build_version)
            .join(os_platform.to_string())
            .join(format!("{bundle_identifier}.dSYM"))
    }

    pub async fn download_device_dsyms(
        &self,
        device_type_identifier: &str,
        os_build_id: &str,
    ) -> Result<PathBuf> {
        // 0. Need to get the firmware UUID and download path from https://api.ipsw.me/v4/
        // 0.5 Need to check our downloads to make sure we don't already have everything downloaded
        // 1. Need to get the ipsw file from the download path retrieved above
        // 2. Need to extract all relevant dSYMs from it using available methods
        // 3. Need to symlink all binaries from from <dsym_path>/cache/<binary_UUID> to the dsym_path
        let _ = (device_type_identifier, os_build_id);
        anyhow::bail!("device dSYM download is not implemented yet")
    }

    pub async fn store_dsym(
        &self,
        build_version: &str,
        bundle_identifier: &str,
        os_platform: &ApplePlatformVersion,
        dsym: Vec<u8>,
    ) -> Result<(), anyhow::Error> {
        let binary_dsym_path = self.binary_dsym_path(build_version, bundle_identifier, os_platform);
        tokio::fs::create_dir_all(binary_dsym_path.parent().unwrap()).await?;
        tokio::fs::write(&binary_dsym_path, dsym).await?;
        self.symlink_dsym_binaries(&binary_dsym_path).await?;
        Ok(())
    }

    pub async fn store_dsym_zip(&self, dsym_zip: Vec<u8>) -> Result<StoredDsymArchive> {
        self.store_dsym_zip_with_metadata(None, dsym_zip).await
    }

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

    async fn symlink_dsym_binaries(&self, binary_dsym_path: &Path) -> anyhow::Result<()> {
        let binary_dsym_path = binary_dsym_path.to_path_buf();
        let symbolication_root = self.symbolication_root.clone();
        tokio::task::spawn_blocking(move || {
            let dwarf_files = find_dwarf_files(&binary_dsym_path)?;
            for dwarf_file in dwarf_files {
                for debug_id in debug_ids_for_macho(&dwarf_file)? {
                    index_debug_file(&symbolication_root, debug_id, &dwarf_file)?;
                }
            }
            Ok(())
        })
        .await
        .context("joining dSYM indexing task")?
    }

    async fn ensure_system_symbols_cached(&self, payload: &MetricKitPayload) -> Result<()> {
        let Some(requirement) = payload.system_symbol_requirement() else {
            return Ok(());
        };

        let dyld_dir = self
            .symbolication_root
            .join("system")
            .join(&requirement.device_type)
            .join(&requirement.build_id)
            .join("dyld");
        if dyld_cache_exists(&dyld_dir, requirement.arch.as_deref()).await? {
            return Ok(());
        }

        tokio::fs::create_dir_all(&dyld_dir)
            .await
            .with_context(|| format!("creating dyld cache directory {}", dyld_dir.display()))?;

        extract_dyld_shared_cache(
            &requirement.device_type,
            &requirement.build_id,
            &dyld_dir,
            requirement.arch.as_deref(),
        )
        .await?;
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

        let symbol_manager = samply_symbols::SymbolManager::with_helper(
            RoamFileAndPathHelper::new(self.symbolication_root.clone(), Uuid::nil()),
        );
        let mut symbolicated_addresses = BTreeMap::new();
        let mut lookup_errors = BTreeMap::new();
        for (breakpad_id, request) in requests {
            match self
                .symbolicate_requested_addresses_for_lib(&breakpad_id, request, &symbol_manager)
                .await
            {
                Ok(result) => {
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
        tokio::fs::write(&report_path, report)
            .await
            .with_context(|| format!("writing symbolicated report {}", report_path.display()))?;
        Ok(report_path)
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MetricKitPayload {
    #[serde(default)]
    time_stamp_begin: Option<String>,
    #[serde(default)]
    time_stamp_end: Option<String>,
    #[serde(default)]
    crash_diagnostics: Vec<MetricKitCrashDiagnostic>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MetricKitCrashDiagnostic {
    #[serde(default)]
    version: Option<String>,
    #[serde(default)]
    call_stack_tree: MetricKitCallStackTree,
    #[serde(default)]
    diagnostic_meta_data: BTreeMap<String, serde_json::Value>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MetricKitCallStackTree {
    #[serde(default)]
    call_stacks: Vec<MetricKitCallStack>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MetricKitCallStack {
    #[serde(default)]
    thread_attributed: bool,
    #[serde(default)]
    call_stack_root_frames: Vec<MetricKitCallStackFrame>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MetricKitCallStackFrame {
    #[serde(default)]
    binary_uuid: Option<String>,
    #[serde(default)]
    binary_name: Option<String>,
    #[serde(default)]
    address: Option<u64>,
    #[serde(default)]
    offset_into_binary_text_segment: Option<u64>,
    #[serde(default)]
    sample_count: Option<u64>,
    #[serde(default)]
    sub_frames: Vec<MetricKitCallStackFrame>,
}

#[derive(Debug)]
struct SystemSymbolRequirement {
    device_type: String,
    build_id: String,
    arch: Option<String>,
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
        Some(SystemSymbolRequirement {
            device_type,
            build_id,
            arch,
        })
    }
}

async fn extract_dyld_shared_cache(
    device_type: &str,
    build_id: &str,
    output_dir: &Path,
    arch: Option<&str>,
) -> Result<()> {
    let mut command = Command::new("ipsw");
    command
        .arg("download")
        .arg("ipsw")
        .arg("--device")
        .arg(device_type)
        .arg("--build")
        .arg(build_id)
        .arg("--dyld")
        .arg("--confirm")
        .arg("--output")
        .arg(output_dir);
    if let Some(arch) = arch {
        command.arg("--dyld-arch").arg(arch);
    }

    let output = command
        .output()
        .await
        .context("running `ipsw download ipsw --dyld`; install https://github.com/blacktop/ipsw to enable automatic system-symbol extraction")?;
    if !output.status.success() {
        anyhow::bail!(
            "`ipsw download ipsw --dyld` failed with status {}: {}{}",
            output.status,
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(())
}

async fn dyld_cache_exists(dyld_dir: &Path, arch: Option<&str>) -> Result<bool> {
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
            let mut symbol = result.symbol_name.clone();
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
    find_dwarf_files_impl(root, &mut result)?;
    Ok(result)
}

fn find_dwarf_files_impl(path: &Path, result: &mut Vec<PathBuf>) -> Result<()> {
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
        for entry in fs::read_dir(path).with_context(|| format!("reading {}", path.display()))? {
            let entry = entry?;
            find_dwarf_files_impl(&entry.path(), result)?;
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

#[derive(Debug)]
struct SymbolInfo {
    symbol_name: String,
    file_name: Option<String>,
    line_number: Option<u64>,
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
}
