
# odinfmt every odin file under this directory or subdirectories
format:
    #! python
    import os, subprocess
    for (root, _, files) in os.walk("."):
        for filename in files:
            if filename.endswith(".odin"):
                path = os.path.join(root, filename)
                subprocess.check_call(f"odinfmt -w {path}", shell=True)


# lint checks for style and potential bugs. Accepts extra args like `--show-timings`as needed
lint *args:
    odin check . -vet -strict-style -no-entry-point {{args}}


# ensure the build artifacts top level directory exists
@mktarget_dirs:
    -mkdir target
    -mkdir target/debug
    -mkdir target/fastdebug
    -mkdir target/release


build_debug *args: mktarget_dirs
    odin build . -debug -microarch:native -show-timings -out:target/debug/main.exe

run_debug: build_debug
    target/debug/main.exe

build_fastdebug *args: mktarget_dirs
    odin build . -debug -o:speed -microarch:native -show-timings -out:target/fastdebug/main.exe

run_fastdebug: build_fastdebug
    target/fastdebug/main.exe

build_release *args: mktarget_dirs
    odin build . -o:speed -microarch:native -show-timings -out:target/release/main.exe

run_release: build_release
    target/release/main.exe

# run all tests
test: mktarget_dirs
    odin test . -debug -file -microarch:native -lld -show-timings -out:target/debug/test-main.exe

# run one named test
test1 name: mktarget_dirs
    odin test . -debug -file -microarch:native -lld -show-timings -test-name:{{name}} -out:target/debug/test-main.exe

# simple delete of all debug databases and executables in the current directory and our executable
clean:
    rm -rf target
    just mktarget_dirs
