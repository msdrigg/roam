//! Private symbol names from a dyld shared cache's `.symbols` subcache.
//!
//! samply reads only the names a cache exports, so UIKit, SwiftUI and
//! QuartzCore internals come back as `<redacted>` or a synthesized `fun_<addr>`.
//! iOS caches ship the stripped names in a separate local-symbols table inside
//! `dyld_shared_cache_<arch>.symbols`, which `ipsw` already downloads.
//!
//! Layout, from dyld's `dyld_cache_format.h` (all little-endian):
//! - main header: `mappingOffset` u32 @16, first mapping's address u64 at
//!   `mappingOffset`, `imagesTextOffset`/`imagesTextCount` u64 @136/@144, each
//!   entry `{ uuid[16], loadAddress u64, textSegmentSize u32, pathOffset u32 }`.
//! - `.symbols` header: `localSymbolsOffset` u64 @72. At that offset,
//!   `{ nlistOffset, nlistCount, stringsOffset, stringsSize, entriesOffset,
//!   entriesCount }` u32s relative to it, entries `{ dylibOffset u64,
//!   nlistStartIndex u32, nlistCount u32 }` where `dylibOffset` is the image's
//!   load address minus the first mapping's address, and `nlist_64` records.

use anyhow::{Context, Result, bail};
use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use uuid::Uuid;

const IMAGES_TEXT_FIELDS_END: u32 = 152;
const LOCAL_SYMBOLS_FIELDS_END: u32 = 88;
const N_STAB: u8 = 0xe0;
const N_TYPE: u8 = 0x0e;
const N_SECT: u8 = 0x0e;

pub struct DyldLocalSymbols {
    symbols_path: PathBuf,
    local_symbols_offset: u64,
    nlist_offset: u64,
    strings_offset: u64,
    strings_size: u64,
    /// UUID to (load address, nlist start index, nlist count).
    images: HashMap<Uuid, (u64, u32, u32)>,
}

/// The containing function's name and the image-relative address it starts at.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalSymbol {
    pub name: String,
    pub start: u32,
}

impl DyldLocalSymbols {
    /// `Ok(None)` when the directory has no main cache with a `.symbols`
    /// sibling, which is normal for macOS caches.
    pub fn open(dyld_dir: &Path, arch: Option<&str>) -> Result<Option<Self>> {
        let Some((main_path, symbols_path)) = find_cache_pair(dyld_dir, arch)? else {
            return Ok(None);
        };

        let mut main =
            File::open(&main_path).with_context(|| format!("opening {}", main_path.display()))?;
        let header = read_at(&mut main, 0, IMAGES_TEXT_FIELDS_END as usize)?;
        check_magic(&header, &main_path)?;
        let mapping_offset = u32_at(&header, 16);
        if mapping_offset < IMAGES_TEXT_FIELDS_END {
            return Ok(None);
        }
        let base = u64_at(&read_at(&mut main, mapping_offset as u64, 8)?, 0);
        let images_text_offset = u64_at(&header, 136);
        let images_text_count = u64_at(&header, 144);
        let images_text = read_at(
            &mut main,
            images_text_offset,
            usize::try_from(images_text_count * 32).context("imagesText too large")?,
        )?;
        let mut load_by_dylib_offset = HashMap::new();
        for entry in images_text.chunks_exact(32) {
            let uuid = Uuid::from_slice(&entry[..16]).expect("16 bytes");
            let load_address = u64_at(entry, 16);
            load_by_dylib_offset.insert(load_address.wrapping_sub(base), (uuid, load_address));
        }

        let mut symbols = File::open(&symbols_path)
            .with_context(|| format!("opening {}", symbols_path.display()))?;
        let symbols_header = read_at(&mut symbols, 0, LOCAL_SYMBOLS_FIELDS_END as usize)?;
        check_magic(&symbols_header, &symbols_path)?;
        if u32_at(&symbols_header, 16) < LOCAL_SYMBOLS_FIELDS_END {
            return Ok(None);
        }
        let local_symbols_offset = u64_at(&symbols_header, 72);
        let info = read_at(&mut symbols, local_symbols_offset, 24)?;
        let nlist_offset = u32_at(&info, 0) as u64;
        let strings_offset = u32_at(&info, 8) as u64;
        let strings_size = u32_at(&info, 12) as u64;
        let entries_offset = u32_at(&info, 16) as u64;
        let entries_count = u32_at(&info, 20) as usize;
        let entries = read_at(
            &mut symbols,
            local_symbols_offset + entries_offset,
            entries_count * 16,
        )?;

        let mut images = HashMap::new();
        for entry in entries.chunks_exact(16) {
            if let Some(&(uuid, load_address)) = load_by_dylib_offset.get(&u64_at(entry, 0)) {
                images.insert(uuid, (load_address, u32_at(entry, 8), u32_at(entry, 12)));
            }
        }
        // No entry lining up with an image means the layout is not the one
        // above; better no names than wrong ones.
        if images.is_empty() {
            bail!(
                "no local-symbols entry in {} matches an image in {}",
                symbols_path.display(),
                main_path.display()
            );
        }

        Ok(Some(Self {
            symbols_path,
            local_symbols_offset,
            nlist_offset,
            strings_offset,
            strings_size,
            images,
        }))
    }

    pub fn has_image(&self, uuid: &Uuid) -> bool {
        self.images.contains_key(uuid)
    }

    /// Looks up image-relative addresses; an address before the image's first
    /// local symbol is left out.
    pub fn lookup(&self, uuid: &Uuid, addresses: &[u32]) -> Result<HashMap<u32, LocalSymbol>> {
        let Some(&(load_address, start_index, count)) = self.images.get(uuid) else {
            return Ok(HashMap::new());
        };
        let mut file = File::open(&self.symbols_path)
            .with_context(|| format!("opening {}", self.symbols_path.display()))?;
        let nlists = read_at(
            &mut file,
            self.local_symbols_offset + self.nlist_offset + start_index as u64 * 16,
            count as usize * 16,
        )?;

        let mut functions: Vec<(u32, u32)> = nlists
            .chunks_exact(16)
            .filter_map(|nlist| {
                let n_type = nlist[4];
                if n_type & N_STAB != 0 || n_type & N_TYPE != N_SECT {
                    return None;
                }
                let relative = u64_at(nlist, 8).checked_sub(load_address)?;
                Some((u32::try_from(relative).ok()?, u32_at(nlist, 0)))
            })
            .collect();
        functions.sort_unstable();

        let mut names = HashMap::new();
        for &address in addresses {
            let index = functions.partition_point(|&(start, _)| start <= address);
            let Some(&(start, string_index)) = index.checked_sub(1).map(|i| &functions[i]) else {
                continue;
            };
            let Some(name) = self.read_name(&mut file, string_index)? else {
                continue;
            };
            names.insert(address, LocalSymbol { name, start });
        }
        Ok(names)
    }

    fn read_name(&self, file: &mut File, string_index: u32) -> Result<Option<String>> {
        let string_index = string_index as u64;
        if string_index >= self.strings_size {
            return Ok(None);
        }
        let offset = self.local_symbols_offset + self.strings_offset + string_index;
        let available = (self.strings_size - string_index).min(4096) as usize;
        let bytes = read_at(file, offset, available)?;
        let end = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
        let name = String::from_utf8_lossy(&bytes[..end]);
        // Mach-O prefixes C and Swift names with `_`; ObjC method names have none.
        let name = name.strip_prefix('_').unwrap_or(&name);
        Ok((!name.is_empty()).then(|| name.to_string()))
    }
}

/// Whether a samply result should give way to the local symbol. A
/// `fun_<start>` name came from the function-starts table, so a local symbol
/// that begins before that start belongs to an earlier function.
pub fn local_name_applies(samply_name: Option<&str>, local: &LocalSymbol) -> bool {
    match samply_name {
        None | Some("<redacted>") => true,
        Some(name) => match name.strip_prefix("fun_") {
            Some(hex) => u32::from_str_radix(hex, 16).is_ok_and(|start| local.start >= start),
            None => false,
        },
    }
}

fn find_cache_pair(dyld_dir: &Path, arch: Option<&str>) -> Result<Option<(PathBuf, PathBuf)>> {
    let Ok(entries) = std::fs::read_dir(dyld_dir) else {
        return Ok(None);
    };
    let mut names: Vec<String> = entries
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    for name in &names {
        let Some(cache_arch) = name.strip_prefix("dyld_shared_cache_") else {
            continue;
        };
        if cache_arch.contains('.') || arch.is_some_and(|arch| cache_arch != arch) {
            continue;
        }
        let symbols = format!("{name}.symbols");
        if names.contains(&symbols) {
            return Ok(Some((dyld_dir.join(name), dyld_dir.join(symbols))));
        }
    }
    Ok(None)
}

fn check_magic(header: &[u8], path: &Path) -> Result<()> {
    if !header.starts_with(b"dyld_v1") {
        bail!("{} is not a dyld shared cache", path.display());
    }
    Ok(())
}

fn read_at(file: &mut File, offset: u64, len: usize) -> Result<Vec<u8>> {
    let mut bytes = vec![0; len];
    file.seek(SeekFrom::Start(offset))?;
    file.read_exact(&mut bytes)
        .with_context(|| format!("reading {len} bytes at offset {offset}"))?;
    Ok(bytes)
}

fn u32_at(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(bytes[offset..offset + 4].try_into().expect("4 bytes"))
}

fn u64_at(bytes: &[u8], offset: usize) -> u64 {
    u64::from_le_bytes(bytes[offset..offset + 8].try_into().expect("8 bytes"))
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASE: u64 = 0x1_8000_0000;
    const LOAD: u64 = 0x1_8475_2000;
    const UUID_BYTES: [u8; 16] = [7; 16];

    /// A main cache with one image and a `.symbols` file naming two functions
    /// in it, plus a debugger stab that must be ignored.
    fn write_fixture(dir: &Path) {
        let mut main = vec![0u8; 0x400];
        main[..16].copy_from_slice(b"dyld_v1  arm64e\0");
        main[16..20].copy_from_slice(&0x200u32.to_le_bytes());
        main[0x200..0x208].copy_from_slice(&BASE.to_le_bytes());
        main[136..144].copy_from_slice(&0x300u64.to_le_bytes());
        main[144..152].copy_from_slice(&1u64.to_le_bytes());
        main[0x300..0x310].copy_from_slice(&UUID_BYTES);
        main[0x310..0x318].copy_from_slice(&LOAD.to_le_bytes());
        std::fs::write(dir.join("dyld_shared_cache_arm64e"), main).unwrap();

        let strings = b"\0_first\0-[UIResponder second]\0stab\0";
        let nlist = |strx: u32, n_type: u8, value: u64| {
            let mut n = vec![0u8; 16];
            n[..4].copy_from_slice(&strx.to_le_bytes());
            n[4] = n_type;
            n[8..].copy_from_slice(&value.to_le_bytes());
            n
        };
        let mut nlists = Vec::new();
        nlists.extend(nlist(8, N_SECT, LOAD + 0x200));
        nlists.extend(nlist(1, N_SECT | 0x01, LOAD + 0x100));
        nlists.extend(nlist(30, 0x24, LOAD + 0x150));

        let info_len = 24u32;
        let entries_offset = info_len;
        let nlist_offset = entries_offset + 16;
        let strings_offset = nlist_offset + nlists.len() as u32;
        let mut local = Vec::new();
        for value in [
            nlist_offset,
            3,
            strings_offset,
            strings.len() as u32,
            entries_offset,
            1,
        ] {
            local.extend(value.to_le_bytes());
        }
        local.extend((LOAD - BASE).to_le_bytes());
        local.extend(0u32.to_le_bytes());
        local.extend(3u32.to_le_bytes());
        local.extend(&nlists);
        local.extend(strings);

        let mut symbols = vec![0u8; 0x100];
        symbols[..16].copy_from_slice(b"dyld_v1  arm64e\0");
        symbols[16..20].copy_from_slice(&0x98u32.to_le_bytes());
        symbols[72..80].copy_from_slice(&0x100u64.to_le_bytes());
        symbols.extend(local);
        std::fs::write(dir.join("dyld_shared_cache_arm64e.symbols"), symbols).unwrap();
    }

    #[test]
    fn names_addresses_from_the_symbols_subcache() {
        let dir = tempfile::tempdir().unwrap();
        write_fixture(dir.path());
        let local = DyldLocalSymbols::open(dir.path(), Some("arm64e"))
            .unwrap()
            .unwrap();
        let uuid = Uuid::from_bytes(UUID_BYTES);
        assert!(local.has_image(&uuid));

        let names = local.lookup(&uuid, &[0x80, 0x120, 0x160, 0x240]).unwrap();
        assert_eq!(names.get(&0x80), None, "before the first symbol");
        let first = LocalSymbol {
            name: "first".into(),
            start: 0x100,
        };
        assert_eq!(names.get(&0x120), Some(&first));
        // The stab at 0x150 is not a function and must not end `first`.
        assert_eq!(names.get(&0x160), Some(&first));
        assert_eq!(names[&0x240].name, "-[UIResponder second]");
        assert_eq!(names[&0x240].start, 0x200);
    }

    #[test]
    fn a_directory_without_a_symbols_file_has_no_local_symbols() {
        let dir = tempfile::tempdir().unwrap();
        write_fixture(dir.path());
        std::fs::remove_file(dir.path().join("dyld_shared_cache_arm64e.symbols")).unwrap();
        assert!(
            DyldLocalSymbols::open(dir.path(), Some("arm64e"))
                .unwrap()
                .is_none()
        );
        assert!(
            DyldLocalSymbols::open(&dir.path().join("missing"), None)
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn a_function_start_name_keeps_an_earlier_local_symbol_out() {
        let local = LocalSymbol {
            name: "earlier".into(),
            start: 0x100,
        };
        assert!(local_name_applies(None, &local));
        assert!(local_name_applies(Some("<redacted>"), &local));
        assert!(local_name_applies(Some("fun_100"), &local));
        assert!(!local_name_applies(Some("fun_180"), &local));
        assert!(!local_name_applies(Some("objc_retain"), &local));
    }

    /// Against a real cache: `ROAM_DYLD_SYMBOLS_DIR` pointing at the iPhone14,3
    /// 24B156 `dyld` directory copied from the symbolicator.
    #[test]
    #[ignore]
    fn resolves_the_keyboard_deadlock_frames_in_a_real_cache() {
        let dir = PathBuf::from(std::env::var("ROAM_DYLD_SYMBOLS_DIR").unwrap());
        let local = DyldLocalSymbols::open(&dir, Some("arm64e"))
            .unwrap()
            .unwrap();
        let uikit = Uuid::parse_str("58942358b42d383b903248516012fb92").unwrap();
        let names = local.lookup(&uikit, &[0x587a5c, 0x75bdd8]).unwrap();
        assert_eq!(
            names[&0x587a5c].name,
            "-[UIResponder(UIResponderInputViewAdditions) inputDashboardViewController]"
        );
        assert_eq!(
            names[&0x75bdd8].name,
            "-[UISystemInputAssistantViewController _customCenterViewController:]"
        );
    }
}
