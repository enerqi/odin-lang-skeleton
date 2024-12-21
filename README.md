# Odin Programming Language Project Skeleton

A minimal project skeleton for writing programs in the [Odin programming language](http://odin-lang.org/)

The build artifacts are output under the `target` directory (similar to [Rust](https://www.rust-lang.org/) projects
built using `cargo`).

A `justfile` is part of this opinionated setup and you may need to edit the tasks as new packages are added in
sub-directories. [Just >=1.32](https://just.systems/) is a CLI task runner that you *need to install*. Any task can be
run with `just TASK` as follows:

* `just run` or `just run_debug`
* `just run_release`
* `just run_fastdebug`
* `just lint`
* `just format`
* `just clean`
* `just test`
* `just test1`
* `just mktarget_dirs`

The tasks are easy to understand:

- the `run_debug` task and alias `run` is very basic (note, edit the task's output executable name as needed), same for
  the other `run_fastdebug` and `run_release` tasks. All of these accept optional extra variadic arguments. Add `--`
  before passing program arguments
- the `lint` task does type checking, lint warnings and style checking. No code generation
- the `format` task requires [python](https://www.python.org/) installed on the `PATH` and also assumes that `odinfmt`
  is in your `PATH`. It will format every `.odin` file under the project tree. The `odinfmt` program can be built from
  its source within the [Odin language server](https://github.com/DanielGavin/ols) code (see `odinfmt.bat` or
  `odinfmt.sh`). The OLS language server is recommended when editing Odin code
- the `clean` task clears the `target` directory and assumes your shell can do `rm -rf` (if not adjust it!)
	- The opinionated default shell on windows is `nushell` (`nu -c`) - this supports `rm -rf`.
	- See [configuring the just shell](https://just.systems/man/en/chapter_63.html?highlight=set%20shell#configuring-the-shell)
- `test` and `test1` tasks call `odin test ...`, also with optional extra variadic arguments
- the `mktarget_dirs` just task is helpful to create the `target` directory tree and auto called by the `run_*` tasks


## [Sublime Text](https://www.sublimetext.com/) editor specific files

The `OdinJustTarget.sublime-build` file is an example [sublime build file](https://www.sublimetext.com/docs/build_systems.html). Delete it if no developer is using sublime text.
The `Odin.sublime-build` file is similar but doesn't assume you have `just` installed.
Same for the very basic `.sublime-project` file.

Rename the `.sublime-project` file to match your project if keeping.

If you install the `.sublime-build` file(s) you get a lot of build options for *compiling* either the individual file
or the current package of the file open in the editor. The artifacts are output to the the `target` directory (or
current directory if not using `just`).

The build options also include *linting* and *testing*.

This is a basic sublime build system and can be improved upon. You may want your own project specific `just` build
tasks or sublime build files. More flexibility is needed if you need things like custom `-define` compile time
parameters or multi stage conditional build steps. Rare custom steps are easy enough to run from the cli with extra
task arguments, but frequently ran things maybe more conveniently executed through a sublime build file and so require
some project specific customisation.

The sublime `.sublime-snippet` example triggers creation of this "main" skeleton, perhaps useful when want a quick
script file without necessarily using the `justfile` for build management. Copy to your sublime `Packages/User` folder.
Similarly, there is a snippet for filling in a new empty Justfile triggered by "odin".


## Language Server Configuration

This is also optional, delete if not needed. As the [Odin language server](https://github.com/DanielGavin/ols) docs
show you can configure OLS settings in ways specific to your editor, often in a global manner - once per all projects.

However, you can also use the `ols.json` file, perhaps to add odin "collections" specific to your project.
This is initially an empty collection list.
