# Odin Programming Language Project Skeleton

A minimal project skeleton for writing programs in the [Odin programming language](http://odin-lang.org/)

The build artifacts are output under the `target` directory (similar to [Rust](https://www.rust-lang.org/) projects
built using `cargo`).

A `justfile` is part of this opinionated setup and you may need to edit the tasks as new packages are added in
sub-directories. [Just](https://just.systems/) is a CLI task runner that you *need to install*:

- the `mktarget_dirs` just task is helpful to create the `target` directory tree
- the `lint` task does type checking, lint warnings and style checking. No code generation
- the `format` task requires [python](https://www.python.org/) installed on the `PATH` and also assumes that `odinfmt`
  is in your `PATH`. It will format every `.odin` file under the project tree. The `odinfmt` program can be built from
  its source within the [Odin language server](https://github.com/DanielGavin/ols) code (see `odinfmt.bat` or
  `odinfmt.sh`), which is recommended when editing Odin code
- the `run_debug` task and alias `run` is very basic (change the executable name as needed), same for the other
  `run_fastdebug` and `run_release` tasks. All of these accept optional extra variadic arguments. Add `--` before
  passing program arguments.
- the `clean` task clears the `target` directory and assumes your shell can do `rm -rf` (if not adjust it!)
	- The opionionated default shell on windows is `nushell` (`nu -c`) - this supports `rm -rf`.
	- See [configuring the just shell](https://just.systems/man/en/chapter_63.html?highlight=set%20shell#configuring-the-shell)
- `test` and `test1` tasks call `odin test ...`, also with optional extra variadic arguments


## [Sublime Text](https://www.sublimetext.com/) editor specific files

The `OdinJustTarget.sublime-build` file is an example [sublime build file](https://www.sublimetext.com/docs/build_systems.html). Delete it if no developer is using sublime text.
Same for the very basic `.sublime-project` file, which you can rename to match your project if it's useful.

If you install this you get a lot of build options for *compiling* either the individual file or the current package of
the file open in the editor. The artifacts are output to the the `target` directory.

The build options also include *linting* and *testing*.

This is a basic sublime build system and can be improved upon. You may want your own project specific `just` build tasks
or sublime build files. More flexibility is needed if you need things like custom `-define` compile time parameters
or multi stage conditional build steps.


## Language Server Configuration

This is also optional, delete if not needed. As the [Odin language server](https://github.com/DanielGavin/ols) docs
show you can configure OLS settings in ways specific to your editor, often in a global manner - once per all projects.

However, you can also use the `ols.json` file, perhaps to add odin "collections" specific to your project.
This is initially an empty collection list.
