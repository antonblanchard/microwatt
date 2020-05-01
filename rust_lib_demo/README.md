I made a minimal Rust demo.

This needs a rebuild of the `core` library with `xargo` (https://github.com/japaric/xargo) for working soft floating-point support.

Steps:

```
$ rustup default nightly

$ rustup target add powerpc64le-unknown-linux-gnu

$ rustup component add rust-src

$ cargo install xargo

$ make
$ make run

ln -sf hello_world.bin main_ram.bin
../core_tb > /dev/null
Hello World
Rust
i 2
5
5
i 3
3.3333333333333335
3.3333333333333335
[-9, -6, 2, 3]
!panicked at 'test', src/lib.rs:58:5

```

