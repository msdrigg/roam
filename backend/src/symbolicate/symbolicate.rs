use crate::database::DeviceInfo;
use crate::diagnostics::*;
use anyhow::{anyhow, Result};
use futures::future::BoxFuture;
use futures::FutureExt;
use samply_symbols::debugid::DebugId;
use samply_symbols::{
    CandidatePathInfo, FileAndPathHelper, FileAndPathHelperResult, FileLocation, FrameDebugInfo,
    FramesLookupResult, LibraryInfo, LookupAddress, OptionallySendFuture,
};
use std::collections::{BTreeMap, HashMap};
use std::fmt::Display;
use std::fs::File;
use std::ops::Deref;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::Arc;
use tracing_subscriber::field::debug;

#[derive(Clone)]
pub struct SymbolicationClient {
    dsym_path: PathBuf,
    symbol_manager: Arc<samply_symbols::SymbolManager<RoamFileAndPathHelper>>,
}

#[derive(Clone)]
pub struct RoamFileAndPathHelper {
    dsym_path: PathBuf,
}

impl RoamFileAndPathHelper {
    pub fn new(dsym_path: PathBuf) -> Self {
        RoamFileAndPathHelper { dsym_path }
    }

    fn cache_dir(&self) -> PathBuf {
        self.dsym_path.join("cache")
    }

    async fn load_file_impl(
        &self,
        location: LocalFilePath,
    ) -> FileAndPathHelperResult<memmap2::Mmap> {
        let file = File::open(location.0)?;
        Ok(unsafe { memmap2::MmapOptions::new().map(&file)? })
    }

    fn expand_library_info(&self, library_info: &mut LibraryInfo) {
        // TODO: Add the path to the lib info if it's not set
        todo!()
    }
}

#[derive(Debug, Clone)]
struct LocalFilePath(PathBuf);

impl Display for LocalFilePath {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0.display())
    }
}

impl FileLocation for LocalFilePath {
    fn location_for_dyld_subcache(&self, suffix: &str) -> Option<Self> {
        // Dyld shared caches are only loaded from local files.
        let mut filename = self.0.file_name().unwrap().to_owned();
        filename.push(suffix);
        Some(Self(self.0.with_file_name(filename)))
    }

    fn location_for_external_object_file(&self, object_file: &str) -> Option<Self> {
        // External object files are referred to by absolute file path, so we only
        // load them if those paths were found in a local file.
        Some(Self(object_file.into()))
    }

    fn location_for_pdb_from_binary(&self, pdb_path_in_binary: &str) -> Option<Self> {
        // We only respect absolute paths to PDB files if those paths were found in a local binary.
        Some(Self(pdb_path_in_binary.into()))
    }

    fn location_for_source_file(&self, source_file_path: &str) -> Option<Self> {
        let debug_file_path = &self.0;
        if source_file_path.starts_with("https://") || source_file_path.starts_with("http://") {
            // Treat the path as a URL. One case where we get URLs is in jitdump files:
            // E.g. profiling a browser which executes JITted JS code from a script on
            // the web will create a jitdump file where the debug information for an
            // address has a URL as the file path.
            //
            // SECURITY: This URL is referred to by a debug file on the local file system.
            // We trust the contents of these files, and we allow them to refer to
            // arbitrary URLs.
            // return Some(Self::UrlForSourceFile(source_file_path.to_owned()));
            return None;
        }
        let source_file_path = Path::new(source_file_path);
        if source_file_path.is_absolute() {
            Some(Self(source_file_path.to_owned()))
        } else {
            // Resolve relative paths with respect to the location of the debug file.
            debug_file_path
                .parent()
                .map(|base_path| Self(base_path.join(source_file_path)))
        }
    }

    fn location_for_breakpad_symindex(&self) -> Option<Self> {
        None
    }

    fn location_for_dwo(&self, comp_dir: &str, path: &str) -> Option<Self> {
        let debug_file_path = &self.0;
        if path.starts_with('/') {
            return Some(Self(path.into()));
        }
        // Resolve relative paths with respect to comp_dir.
        if comp_dir.starts_with('/') {
            let comp_dir = comp_dir.trim_end_matches('/');
            let dwo_path = format!("{comp_dir}/{path}");
            return Some(Self(Path::new(&dwo_path).into()));
        }
        // Resolve relative paths with respect to the location of the debug file.
        debug_file_path
            .parent()
            .map(|base_path| Self(base_path.join(comp_dir).join(path)))
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
        let binary_path = &self.0;
        let mut dwp_path = binary_path.as_os_str().to_os_string();
        dwp_path.push(".dwp");
        Some(Self(dwp_path.into()))
    }
}

impl FileAndPathHelper for RoamFileAndPathHelper {
    type F = memmap2::Mmap;
    type FL = LocalFilePath;

    fn get_candidate_paths_for_debug_file(
        &self,
        library_info: &LibraryInfo,
    ) -> FileAndPathHelperResult<Vec<CandidatePathInfo<LocalFilePath>>> {
        let mut library_info = library_info.clone();
        self.expand_library_info(&mut library_info);

        if let Some(uuid) = library_info.debug_id.as_ref().map(|id| id.uuid()) {
            let cache_dir = self.cache_dir();
            let mut options = Vec::new();

            // Add uuid.dSYM to the binary
            options.push(CandidatePathInfo::SingleFile(LocalFilePath(
                cache_dir.join("dsym").join(format!("{}", uuid)),
            )));

            if let Some(debug_name) = &library_info.debug_name {
                // Add uuid.dSYM to the binary with a .dSYM suffix
                options.push(CandidatePathInfo::SingleFile(LocalFilePath(
                    cache_dir
                        .join("dsym")
                        .join(format!("{}", uuid))
                        .join("Contents")
                        .join("Resources")
                        .join("DWARF")
                        .join(debug_name),
                )));
            }

            if let Ok(dyld_cache_paths) =
                self.get_dyld_shared_cache_paths(library_info.arch.as_deref())
            {
                if let Some(path) = library_info.path.as_ref() {
                    for dyld_cache_path in dyld_cache_paths {
                        options.push(CandidatePathInfo::InDyldCache {
                            dyld_cache_path,
                            dylib_path: path.clone(),
                        });
                    }
                }
            }

            options.push(CandidatePathInfo::SingleFile(LocalFilePath(
                cache_dir.join("so").join(format!("{}", uuid)),
            )));

            FileAndPathHelperResult::Ok(options)
        } else {
            tracing::warn!(?library_info, "No debug ID found for library");

            FileAndPathHelperResult::Err(Box::new(
                samply_symbols::Error::NotEnoughInformationToIdentifyBinary,
            ))
        }
    }

    fn get_candidate_paths_for_binary(
        &self,
        library_info: &LibraryInfo,
    ) -> FileAndPathHelperResult<Vec<CandidatePathInfo<LocalFilePath>>> {
        return self.get_candidate_paths_for_debug_file(library_info);
    }

    fn get_dyld_shared_cache_paths(
        &self,
        arch: Option<&str>,
    ) -> FileAndPathHelperResult<Vec<LocalFilePath>> {
        let mut vec = Vec::new();

        let mut add_entries_in_dir = |dir: &str| {
            let mut add_entry_for_arch = |arch: &str| {
                let path = format!("{dir}/dyld_shared_cache_{arch}");
                vec.push(LocalFilePath(PathBuf::from(path)));
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

        // macOS 13+ (we only support macOS 13+, so we can ignore the older paths)
        add_entries_in_dir("/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld");

        Ok(vec)
    }

    fn load_file(
        &self,
        location: LocalFilePath,
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
    pub fn new(dsym_path: PathBuf) -> Self {
        SymbolicationClient {
            dsym_path: dsym_path.clone(),
            symbol_manager: Arc::new(samply_symbols::SymbolManager::with_helper(
                RoamFileAndPathHelper::new(dsym_path.clone()),
            )),
        }
    }

    async fn symbolicate_requested_addresses_for_lib(
        &self,
        breakpad_id: &str,
        mut addresses: Vec<u32>,
    ) -> Result<LookedUpAddresses, samply_symbols::Error> {
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

        let info = LibraryInfo {
            debug_name: None,
            debug_id: Some(debug_id),
            ..Default::default()
        };
        let symbol_map = self.symbol_manager.load_symbol_map(&info).await?;

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

pub struct SymbolicatedFrame {
    pub original_frame: Frame,
    pub symbol_name: Option<String>,
    pub file_name: Option<String>,
    pub line_number: Option<u64>,
    pub symbolicated_description: Option<String>,
    pub error: Option<String>,
    pub subframes: Option<Vec<SymbolicatedFrame>>,
}

pub struct SymbolicatedCallStack {
    pub thread_attributed: bool,
    pub frames: Vec<SymbolicatedFrame>,
}

struct SymbolicatedDiagnosticInternal {
    pub diagnostic_type: String,
    pub metadata: HashMap<String, String>,
    pub call_stacks: Vec<SymbolicatedCallStack>,
    pub summary: String,
}

impl SymbolicatedDiagnosticInternal {
    pub fn report(&self) -> String {
        let mut report = format!("Type: {}\n", self.diagnostic_type);
        report += "Metadata:\n";
        for (key, value) in &self.metadata {
            report += &format!("  {}: {}\n", key, value);
        }
        report += "Call Stacks:\n";
        for stack in &self.call_stacks {
            report += &format!("  Thread Attributed: {}\n", stack.thread_attributed);
            for frame in &stack.frames {
                report += &format!(
                    "    Frame: {} ({}:{})\n",
                    frame.symbol_name.as_deref().unwrap_or("unknown"),
                    frame.file_name.as_deref().unwrap_or("unknown"),
                    frame.line_number.unwrap_or(0)
                );
            }
        }
        report += &format!("Summary: {}\n", self.summary);
        report
    }
}

pub struct SymbolicatedDiagnostics {
    pub notable_info: String,
    pub report: String,
}

pub enum ApplePlatformVersion {
    IOs,
    MacOs,
    VisionOs,
    WatchOs,
}

impl Display for ApplePlatformVersion {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ApplePlatformVersion::IOs => write!(f, "iOS"),
            ApplePlatformVersion::MacOs => write!(f, "macOS"),
            ApplePlatformVersion::VisionOs => write!(f, "visionOS"),
            ApplePlatformVersion::WatchOs => write!(f, "watchOS"),
        }
    }
}
impl FromStr for ApplePlatformVersion {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "ios" => Ok(ApplePlatformVersion::IOs),
            "macos" => Ok(ApplePlatformVersion::MacOs),
            "visionos" => Ok(ApplePlatformVersion::VisionOs),
            "watchos" => Ok(ApplePlatformVersion::WatchOs),
            _ => Err(anyhow!("Unknown OS version: {}", s)),
        }
    }
}

impl SymbolicationClient {
    // Placeholder methods that you would implement based on your storage
    fn device_dsym_dir(&self, device_uuid: &str) -> PathBuf {
        self.dsym_path.join("device-dsyms").join(device_uuid)
    }

    fn dsym_cache_dir(&self) -> PathBuf {
        self.dsym_path.join("cache")
    }

    fn binary_dsym_path(
        &self,
        build_version: &str,
        bundle_identifier: &str,
        os_platform: &ApplePlatformVersion,
    ) -> PathBuf {
        self.dsym_path
            .join("binaries")
            .join(build_version)
            .join(os_platform.to_string())
            .join(format!("{}.dSYM", bundle_identifier))
    }

    pub async fn download_device_dsyms(
        &self,
        device_type_identifier: &str,
        os_build_id: &str,
    ) -> Result<PathBuf> {
        let device_dsym_path = self
            .dsym_path
            .join("device-dsyms")
            .join(device_type_identifier)
            .join(os_build_id);

        tokio::fs::create_dir_all(&device_dsym_path).await?;

        // 1. Need to get the ipsw file from https://api.ipsw.me/v4/ipsw/download/identifier/buildid
        // 2. Need to extract all relevant dSYMs from it using available methods
        // 3. Need to symlink all binaries from from <dsym_path>/cache/<binary_UUID> to the dsym_path
        todo!()
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

    async fn symlink_dsym_binaries(&self, binary_dsym_path: &Path) -> anyhow::Result<()> {
        // TODO: Get the UUIDs of the binaries from the dSYM
        // TODO: Then create symlinks in the dsym_path/cache/<binary_UUID> to the actual binary files
        let cache_dir = self.dsym_cache_dir();
        todo!()
    }
}

impl SymbolicationClient {
    pub async fn symbolicate_diagnostics(
        &self,
        device_id: &str,
        diagnostics: &RoamDebugInfo,
        metrics_payload: &[RoamMetricDiagnosticPayload],
        installation_info: &DeviceInfo,
    ) -> Vec<SymbolicatedDiagnostics> {
        let mut results = Vec::new();

        for payload in metrics_payload {
            // Process crash diagnostics
            for crash_diag in &payload.crash_diagnostics {
                if let Some(symbolicated) = self
                    .symbolicate_crash_diagnostic(device_id, crash_diag, installation_info)
                    .await
                {
                    results.push(symbolicated);
                }
            }

            // Process CPU exception diagnostics
            for cpu_diag in &payload.cpu_exception_diagnostics {
                if let Some(symbolicated) = self
                    .symbolicate_cpu_diagnostic(device_id, cpu_diag, installation_info)
                    .await
                {
                    results.push(symbolicated);
                }
            }

            // Process disk write diagnostics
            for disk_diag in &payload.disk_write_exception_diagnostics {
                if let Some(symbolicated) = self
                    .symbolicate_disk_diagnostic(device_id, disk_diag, installation_info)
                    .await
                {
                    results.push(symbolicated);
                }
            }

            // Process hang diagnostics
            for hang_diag in &payload.hang_diagnostics {
                if let Some(symbolicated) = self
                    .symbolicate_hang_diagnostic(device_id, hang_diag, installation_info)
                    .await
                {
                    results.push(symbolicated);
                }
            }

            // Process app launch diagnostics
            for launch_diag in &payload.app_launch_diagnostics {
                if let Some(symbolicated) = self
                    .symbolicate_app_launch_diagnostic(device_id, launch_diag, installation_info)
                    .await
                {
                    results.push(symbolicated);
                }
            }
        }

        results
            .into_iter()
            .map(|sd| SymbolicatedDiagnostics {
                notable_info: sd.summary.clone(),
                report: sd.report(),
            })
            .collect()
    }

    async fn symbolicate_crash_diagnostic(
        &self,
        device_id: &str,
        diagnostic: &CrashDiagnostic,
        installation_info: &DeviceInfo,
    ) -> Option<SymbolicatedDiagnosticInternal> {
        let mut metadata = HashMap::new();
        metadata.insert(
            "exception_type".to_string(),
            diagnostic
                .exception_type
                .map(|t| t.to_string())
                .unwrap_or_default(),
        );
        metadata.insert(
            "exception_code".to_string(),
            diagnostic
                .exception_code
                .map(|c| c.to_string())
                .unwrap_or_default(),
        );
        metadata.insert(
            "signal".to_string(),
            diagnostic.signal.map(|s| s.to_string()).unwrap_or_default(),
        );
        metadata.insert(
            "application_version".to_string(),
            diagnostic.application_version.clone(),
        );
        metadata.insert(
            "os_version".to_string(),
            diagnostic.meta_data.os_version.clone(),
        );

        if let Some(termination_reason) = &diagnostic.termination_reason {
            metadata.insert("termination_reason".to_string(), termination_reason.clone());
        }

        let call_stacks = if let Some(stack_trace) = &diagnostic.stack_trace {
            self.symbolicate_stack_trace(
                device_id,
                stack_trace,
                &diagnostic.meta_data,
                installation_info,
            )
            .await
        } else {
            Vec::new()
        };

        let summary = self.format_crash_summary(&diagnostic);

        Some(SymbolicatedDiagnosticInternal {
            diagnostic_type: "crash".to_string(),
            metadata,
            call_stacks,
            summary,
        })
    }

    async fn symbolicate_cpu_diagnostic(
        &self,
        device_id: &str,
        diagnostic: &CpuExceptionDiagnostic,
        installation_info: &DeviceInfo,
    ) -> Option<SymbolicatedDiagnosticInternal> {
        let mut metadata = HashMap::new();
        metadata.insert(
            "total_cpu_time".to_string(),
            diagnostic.total_cpu_time.to_string(),
        );
        metadata.insert(
            "total_sampled_time".to_string(),
            diagnostic.total_sampled_time.to_string(),
        );
        metadata.insert(
            "application_version".to_string(),
            diagnostic.application_version.clone(),
        );
        metadata.insert(
            "os_version".to_string(),
            diagnostic.meta_data.os_version.clone(),
        );

        let call_stacks = if let Some(stack_trace) = &diagnostic.stack_trace {
            self.symbolicate_stack_trace(
                device_id,
                stack_trace,
                &diagnostic.meta_data,
                installation_info,
            )
            .await
        } else {
            Vec::new()
        };

        let summary = format!(
            "CPU Exception: {:.2}s CPU time out of {:.2}s sampled",
            diagnostic.total_cpu_time, diagnostic.total_sampled_time
        );

        Some(SymbolicatedDiagnosticInternal {
            diagnostic_type: "cpu_exception".to_string(),
            metadata,
            call_stacks,
            summary,
        })
    }

    async fn symbolicate_disk_diagnostic(
        &self,
        device_id: &str,
        diagnostic: &DiskWriteExceptionDiagnostic,
        installation_info: &DeviceInfo,
    ) -> Option<SymbolicatedDiagnosticInternal> {
        let mut metadata = HashMap::new();
        metadata.insert(
            "total_writes".to_string(),
            diagnostic.total_writes.to_string(),
        );
        metadata.insert(
            "application_version".to_string(),
            diagnostic.application_version.clone(),
        );
        metadata.insert(
            "os_version".to_string(),
            diagnostic.meta_data.os_version.clone(),
        );

        let call_stacks = if let Some(stack_trace) = &diagnostic.stack_trace {
            self.symbolicate_stack_trace(
                device_id,
                stack_trace,
                &diagnostic.meta_data,
                installation_info,
            )
            .await
        } else {
            Vec::new()
        };

        let summary = format!(
            "Disk Write Exception: {:.2} writes",
            diagnostic.total_writes
        );

        Some(SymbolicatedDiagnosticInternal {
            diagnostic_type: "disk_write_exception".to_string(),
            metadata,
            call_stacks,
            summary,
        })
    }

    async fn symbolicate_hang_diagnostic(
        &self,
        device_id: &str,
        diagnostic: &HangDiagnostic,
        installation_info: &DeviceInfo,
    ) -> Option<SymbolicatedDiagnosticInternal> {
        let mut metadata = HashMap::new();
        metadata.insert(
            "hang_duration".to_string(),
            diagnostic.hang_duration.to_string(),
        );
        metadata.insert(
            "application_version".to_string(),
            diagnostic.application_version.clone(),
        );
        metadata.insert(
            "os_version".to_string(),
            diagnostic.meta_data.os_version.clone(),
        );

        let call_stacks = if let Some(stack_trace) = &diagnostic.stack_trace {
            self.symbolicate_stack_trace(
                device_id,
                stack_trace,
                &diagnostic.meta_data,
                installation_info,
            )
            .await
        } else {
            Vec::new()
        };

        let summary = format!("Hang: {:.2}s duration", diagnostic.hang_duration);

        Some(SymbolicatedDiagnosticInternal {
            diagnostic_type: "hang".to_string(),
            metadata,
            call_stacks,
            summary,
        })
    }

    async fn symbolicate_app_launch_diagnostic(
        &self,
        device_id: &str,
        diagnostic: &AppLaunchDiagnostic,
        installation_info: &DeviceInfo,
    ) -> Option<SymbolicatedDiagnosticInternal> {
        let mut metadata = HashMap::new();
        metadata.insert(
            "launch_duration".to_string(),
            diagnostic.launch_duration.to_string(),
        );
        metadata.insert(
            "application_version".to_string(),
            diagnostic.application_version.clone(),
        );
        metadata.insert(
            "os_version".to_string(),
            diagnostic.meta_data.os_version.clone(),
        );

        let call_stacks = if let Some(stack_trace) = &diagnostic.stack_trace {
            self.symbolicate_stack_trace(
                device_id,
                stack_trace,
                &diagnostic.meta_data,
                installation_info,
            )
            .await
        } else {
            Vec::new()
        };

        let summary = format!("App Launch: {:.2}s duration", diagnostic.launch_duration);

        Some(SymbolicatedDiagnosticInternal {
            diagnostic_type: "app_launch".to_string(),
            metadata,
            call_stacks,
            summary,
        })
    }

    async fn symbolicate_stack_trace(
        &self,
        device_id: &str,
        stack_trace: &StackTrace,
        metadata: &MetaData,
        installation_info: &DeviceInfo,
    ) -> Vec<SymbolicatedCallStack> {
        let mut result = Vec::new();
        let device_id: Arc<str> = Arc::from(device_id);
        let metadata = Arc::new(metadata.clone());
        let installation_info = Arc::new(installation_info.clone());

        for call_stack in &stack_trace.call_stacks {
            let mut symbolicated_frames = Vec::new();

            for frame in call_stack.call_stack_root_frames.iter().cloned() {
                let symbolicated_frame = self
                    .symbolicate_frame_recursive(
                        device_id.clone(),
                        frame,
                        metadata.clone(),
                        installation_info.clone(),
                    )
                    .await;
                symbolicated_frames.push(symbolicated_frame);
            }

            result.push(SymbolicatedCallStack {
                thread_attributed: call_stack.thread_attributed,
                frames: symbolicated_frames,
            });
        }

        result
    }

    fn symbolicate_frame_recursive(
        &self,
        device_id: Arc<str>,
        frame: Frame,
        metadata: Arc<MetaData>,
        installation_info: Arc<DeviceInfo>,
    ) -> BoxFuture<'static, SymbolicatedFrame> {
        let cloned_client = self.clone();
        return async move {
            let mut symbolicated_frame = cloned_client
                .symbolicate_single_frame(
                    device_id.as_ref(),
                    &frame,
                    metadata.as_ref(),
                    installation_info.as_ref(),
                )
                .await;

            if let Some(subframes) = &frame.subframes {
                let mut symbolicated_subframes: Vec<SymbolicatedFrame> = Vec::new();
                for subframe in subframes.deref().iter().cloned() {
                    let client_cloned = cloned_client.clone();
                    let device_id = device_id.clone();
                    let metadata = metadata.clone();
                    let installation_info = installation_info.clone();

                    let symbolicated_subframe = client_cloned
                        .symbolicate_frame_recursive(
                            device_id,
                            subframe,
                            metadata,
                            installation_info,
                        )
                        .await;

                    symbolicated_subframes.push(symbolicated_subframe);
                }
                symbolicated_frame.subframes = Some(symbolicated_subframes);
            }

            symbolicated_frame
        }
        .boxed();
    }

    fn format_crash_summary(&self, diagnostic: &CrashDiagnostic) -> String {
        let exception_type_name = match diagnostic.exception_type {
            Some(1) => "EXC_BAD_ACCESS",
            Some(2) => "EXC_BAD_INSTRUCTION",
            Some(3) => "EXC_ARITHMETIC",
            Some(4) => "EXC_EMULATION",
            Some(5) => "EXC_SOFTWARE",
            Some(6) => "EXC_BREAKPOINT",
            Some(7) => "EXC_SYSCALL",
            Some(8) => "EXC_MACH_SYSCALL",
            Some(9) => "EXC_RPC_ALERT",
            Some(10) => "EXC_CRASH",
            Some(11) => "EXC_RESOURCE",
            Some(12) => "EXC_GUARD",
            Some(13) => "EXC_CORPSE_NOTIFY",
            _ => "UNKNOWN",
        };

        let signal_name = match diagnostic.signal {
            Some(9) => "SIGKILL",
            Some(11) => "SIGSEGV",
            Some(6) => "SIGABRT",
            Some(4) => "SIGILL",
            _ => "UNKNOWN",
        };

        format!(
            "Crash: {} ({}), Signal: {} ({})",
            exception_type_name,
            diagnostic.exception_type.unwrap_or(0),
            signal_name,
            diagnostic.signal.unwrap_or(0)
        )
    }
}

#[derive(Debug)]
struct SymbolInfo {
    symbol_name: String,
    file_name: Option<String>,
    line_number: Option<u64>,
}
