#![no_std]
#![feature(alloc_error_handler)]

use core::fmt::Write;
use core::panic::PanicInfo;

use heapless::consts::*;
use heapless::String;

extern crate linked_list_allocator;
use linked_list_allocator::*;
#[global_allocator]
static mut HEAP: LockedHeap = LockedHeap::empty();

extern crate alloc;
use alloc::vec::Vec;

extern crate cty;

extern "C" {
    fn putchar(c: cty::c_char) -> ();
    fn crash() -> ();
}

pub fn print(s: &str) {
    for c in s.bytes() {
        unsafe { putchar(c) };
    }
}

#[no_mangle]
pub extern "C" fn rust_main() -> ! {
    print("Rust\r\n");

    const HEAP_SIZE: usize = 2048;
    static mut HEAP_AREA: [u8; HEAP_SIZE] = [0; HEAP_SIZE];
    unsafe { HEAP = LockedHeap::new(&HEAP_AREA[0] as *const u8 as usize, HEAP_AREA.len()) };

    let mut s: String<U128> = String::new();
    let mut xs = Vec::new();
    for i in 2..=3 {
        xs.push(i);
        xs.push(-3 * i);
        xs.push(i);
        writeln!(s, "i {}\r", i).unwrap();
        print(&s);
        s.clear();
        writeln!(s, "{}\r", 10.0 / i as f64).ok();
        print(&s);
        if xs.pop().unwrap() != i {
            panic!("??");
        }
    }
    xs.sort();
    writeln!(s, "{:?}\r", xs).unwrap();
    print(&s);

    panic!("test");
}

#[panic_handler]
fn panic(panic_info: &PanicInfo) -> ! {
    unsafe {
        putchar('!' as u8);
    }
    let mut s: String<U128> = String::new();
    writeln!(s, "{}\r", panic_info).ok();
    print(&s);
    unsafe {
        crash();
    }
    loop {}
}

#[alloc_error_handler]
fn alloc_error(_: core::alloc::Layout) -> ! {
    panic!("Heap");
}
