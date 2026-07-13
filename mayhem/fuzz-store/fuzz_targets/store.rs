//! Fuzz persistent_store's host-side storage path: Linear<RamStorage> writes,
//! erases and reads over arbitrary ranges/page geometries, differentially
//! checked against a shadow byte model.
#![no_main]
use libfuzzer_sys::fuzz_target;
use persistent_store::{Linear, Storage, StorageError, StorageIndex, StorageResult};
use std::borrow::Cow;

struct RamStorage {
    page_size: usize,
    pages: Vec<Vec<u8>>,
}

impl RamStorage {
    fn new(num_pages: usize, page_size: usize) -> Self {
        RamStorage { page_size, pages: vec![vec![0xff; page_size]; num_pages] }
    }
}

impl Storage for RamStorage {
    fn word_size(&self) -> usize {
        4
    }
    fn page_size(&self) -> usize {
        self.page_size
    }
    fn num_pages(&self) -> usize {
        self.pages.len()
    }
    fn max_word_writes(&self) -> usize {
        usize::MAX
    }
    fn max_page_erases(&self) -> usize {
        usize::MAX
    }
    fn read_slice(&self, index: StorageIndex, length: usize) -> StorageResult<Cow<'_, [u8]>> {
        let range = index.range(length, self)?;
        let byte = range.start % self.page_size;
        Ok(Cow::Borrowed(&self.pages[index.page][byte..byte + length]))
    }
    fn write_slice(&mut self, index: StorageIndex, value: &[u8]) -> StorageResult<()> {
        if index.byte % self.word_size() != 0 || value.len() % self.word_size() != 0 {
            return Err(StorageError::NotAligned);
        }
        let range = index.range(value.len(), self)?;
        let byte = range.start % self.page_size;
        self.pages[index.page][byte..byte + value.len()].copy_from_slice(value);
        Ok(())
    }
    fn erase_page(&mut self, page: usize) -> StorageResult<()> {
        if page >= self.pages.len() {
            return Err(StorageError::OutOfBounds);
        }
        self.pages[page].fill(0xff);
        Ok(())
    }
}

fuzz_target!(|data: &[u8]| {
    let mut input = data;
    let mut next = |n: usize| -> Option<Vec<u8>> {
        if input.len() < n {
            return None;
        }
        let (head, tail) = input.split_at(n);
        input = tail;
        Some(head.to_vec())
    };

    let cfg = match next(2) {
        Some(c) => c,
        None => return,
    };
    let num_pages = 1 + (cfg[0] as usize % 8);
    let page_size = 64usize << (cfg[1] as usize % 4); // 64..512, word-multiple
    let length = num_pages * page_size;

    let mut linear = Linear { storage: RamStorage::new(num_pages, page_size) };
    let mut model = vec![0xffu8; length];

    while let Some(op) = next(5) {
        let a = u16::from_le_bytes([op[1], op[2]]) as usize % (length + 1);
        let b = u16::from_le_bytes([op[3], op[4]]) as usize % (length + 1);
        let (lo, hi) = if a <= b { (a, b) } else { (b, a) };
        match op[0] % 3 {
            0 => {
                let payload = match next(hi - lo) {
                    Some(p) => p,
                    None => break,
                };
                linear.write(lo, &payload).expect("in-bounds write must succeed");
                model[lo..hi].copy_from_slice(&payload);
            }
            1 => {
                linear.erase(lo..hi).expect("in-bounds erase must succeed");
                model[lo..hi].fill(0xff);
            }
            _ => {
                let got = linear.read(lo..hi).expect("in-bounds read must succeed");
                assert_eq!(&got[..], &model[lo..hi], "Linear::read diverged from model");
            }
        }
    }

    // Out-of-bounds accesses must error, never panic or wrap.
    assert!(linear.read(0..length + 1).is_err());
    assert!(linear.write(length, &[0u8; 4]).is_err());
});
