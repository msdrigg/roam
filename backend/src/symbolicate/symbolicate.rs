use crate::database::DeviceInfo;
use crate::symbolicate::{ApplePlatformVersion, RoamDebugInfo};
use anyhow::Result;
use samply_symbols::debugid::DebugId;
use samply_symbols::{
    CandidatePathInfo, FileAndPathHelper, FileAndPathHelperResult, FileLocation, FrameDebugInfo,
    FramesLookupResult, LibraryInfo, LookupAddress, OptionallySendFuture, SymbolManager,
};
use std::collections::BTreeMap;
use std::fmt::Display;
use std::fs::File;
use std::path::{Path, PathBuf};
use uuid::Uuid;

#[derive(Clone)]
pub struct SymbolicationClient {
    symbolication_root: PathBuf,
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
        // TODO: Add the path to the lib info if it's not set
        // Copy work from mxsymbolicate...
        todo!()
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
            return Some(self.with_path(self.device_path().join(&dwo_path).into()));
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

        // Need to work on my process for this
        // Where am I storing the device files
        // Where am I storing the binaries
        // What about dyld shared cache?
        // Still not sure about symlinking binaries in the cache, but this might work... How would work for dyld_shared_caches...
        // We could do something else with RoamFileLocation like RoamFileLocation::DatabaseReferenced because this fn isn't async
        // Reference how wholesym handles shared caches...
        // We could also ignore shared cache totally
        todo!();
        // if let Some(uuid) = library_info.debug_id.as_ref().map(|id| id.uuid()) {
        //     let cache_dir = self.cache_dir();
        //     let mut options = Vec::new();

        //     // Add uuid.dSYM to the binary
        //     options.push(CandidatePathInfo::SingleFile(RoamFileLocation(
        //         cache_dir.join("dsym").join(format!("{}", uuid)),
        //     )));

        //     if let Some(debug_name) = &library_info.debug_name {
        //         // Add uuid.dSYM to the binary with a .dSYM suffix
        //         options.push(CandidatePathInfo::SingleFile(RoamFileLocation(
        //             cache_dir
        //                 .join("dsym")
        //                 .join(format!("{}", uuid))
        //                 .join("Contents")
        //                 .join("Resources")
        //                 .join("DWARF")
        //                 .join(debug_name),
        //         )));
        //     }

        //     if let Ok(dyld_cache_paths) =
        //         self.get_dyld_shared_cache_paths(library_info.arch.as_deref())
        //     {
        //         if let Some(path) = library_info.path.as_ref() {
        //             for dyld_cache_path in dyld_cache_paths {
        //                 options.push(CandidatePathInfo::InDyldCache {
        //                     dyld_cache_path,
        //                     dylib_path: path.clone(),
        //                 });
        //             }
        //         }
        //     }

        //     options.push(CandidatePathInfo::SingleFile(RoamFileLocation(
        //         cache_dir.join("so").join(format!("{}", uuid)),
        //     )));

        //     FileAndPathHelperResult::Ok(options)
        // } else {
        //     tracing::warn!(?library_info, "No debug ID found for library");

        //     FileAndPathHelperResult::Err(Box::new(
        //         samply_symbols::Error::NotEnoughInformationToIdentifyBinary,
        //     ))
        // }
    }

    fn get_candidate_paths_for_binary(
        &self,
        library_info: &LibraryInfo,
    ) -> FileAndPathHelperResult<Vec<CandidatePathInfo<RoamFileLocation>>> {
        return self.get_candidate_paths_for_debug_file(library_info);
    }

    fn get_dyld_shared_cache_paths(
        &self,
        arch: Option<&str>,
    ) -> FileAndPathHelperResult<Vec<RoamFileLocation>> {
        let mut vec = Vec::new();

        let mut add_entries_in_dir = |dir: &str| {
            let mut add_entry_for_arch = |arch: &str| {
                let path = format!("{dir}/dyld_shared_cache_{arch}");
                vec.push(RoamFileLocation {
                    path: PathBuf::from(path),
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

        // macOS 13+ (we only support macOS 13+, so we can ignore the older paths)
        add_entries_in_dir("/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld");

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
        mut addresses: Vec<u32>,
        symbol_manager: &SymbolManager<impl FileAndPathHelper>,
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
            .join(format!("{}.dSYM", bundle_identifier))
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
        let device_uuid: Uuid = todo!();

        let device_dsym_path = self
            .symbolication_root
            .join("device-roots")
            .join(device_uuid.to_string());

        tokio::fs::create_dir_all(&device_dsym_path).await?;
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
        // TODO: Then create symlinks in the symbolication_path_root/cache/<binary_UUID> to the actual binary files
        todo!()
    }
}

impl SymbolicationClient {
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

        // TODO: Load the diagnostics from the file, symbolicate them into a report, and then output the report to a path
        // TODO: Get the device_uuid from ipsw API and make sure the files are loaded
        let device_uuid = todo!();

        let symbol_manager = samply_symbols::SymbolManager::with_helper(
            RoamFileAndPathHelper::new(self.symbolication_root.clone(), device_uuid),
        );
        todo!()
    }
}

#[derive(Debug)]
struct SymbolInfo {
    symbol_name: String,
    file_name: Option<String>,
    line_number: Option<u64>,
}
