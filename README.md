# installation/provisioning utility

some of us believe that well-organized scripts are still more powerful than
any of the provisioning and deployment tools out there.

this is an example of a highly opinionated, but therefore dead-simple setup
for provisioning and deployment.

## shell
the shell is an interactive, bash-based shell, that offers various utilities to
debug and installations scripts. it is typically useful for setting up new
environments and to debug the build process. if the build or the install fails,
the shell asks you if you want to restart, so you can easily try again. using
the `debug` command, you can trace the build and/or installation process.

## app configuration
all app configuration is within the `apps/` directory. each subdirectory is
considered an 'app', though this name is somewhat arbitrary. an app can install
multiple applications, do some server configuration, or whatever. in essence,
anything that can be installed as a 'unit', can be it's own app, but typically
single applications will have their own app directory.

within the app's directory, there are two special files and two special
directories. the files are `build.sh` and `install.sh`, and the directories are
`resources` and `artifacts`.

the build script is used to do a local build of the application's artifacts,
and the `install.sh` is executed within the server's shell to actually run the
application.

resources and artifacts are other "things" that need to be available to the
application at the server the application is installed on. artifacts are
created by the build, resources aren't and may be used for local configuration
(to read in the build.sh script) or for remote configuration, e.g. a common
configuration file that is the same on all environments.  you can use the
`$artifacts` and `$resources` variables to access these directories.

since the build results are environment specific, artifacts will be made
available per-environment.

when installing an app, the following steps are applied.

1. first the app's `build.sh` file is called. see the variables section below
   to see which variables are exposed to the script. note that the shell, the
   user's environment
2. then the resources and artifacts are copied to the remote, or they are made
   available to the install script if the build is local (in `development`).
   these directories are available as the `$resources` and `$artifacts` 
   directory respectively. for example, the `build.sh` file may write an
   environment-specific configuration file to the `$artifacts` directory, 
   which can subsequently be used by the install.sh script to configure 
   the application.

## variables
the following variables are available to all build and install scripts:

- `$env` - the current target environment.
- `$docker_host` - the docker image prefix for the location where the images
  are hosted.
- `$namespace` - the project's namespace, useful for prefixing.
- `$app` - the name of the app.
- `$resources` - a full path to the resources directory of the app.
- `$artifacts` - a full path to the artifacts directory for the current
  environment of the app.

the following are currently implemented as 'project-specific' in vars.sh:
- `$network` - the docker network name
- `$name` - the docker image name
- `$docker_opts` - a convenience string supplying name, ip and network as a set
  of docker options.

To copy vars from the build environment to the installation environment, a
utility variable called 'build_vars' is read to declare the variable's value
after build. This variable is declared within 'var.sh' (if available) and can
be extended per-app. For example, if there is a variable named in `project.sh`,
that should be available in `install.sh`, then it should be added to
`$build_vars` in `build.sh` as such:

```bash
build_vars="$build_vars MY_VAR"
```

## Using directly
```
./install.sh [ENV] [APPS...]
```

## Using the shell
1. Start the shell: `./shell.sh`
2. The shell defaults to environment "development". Switch to a different
   target env 
   if you want to install on another server: `env testing`
3. Run the installation script for the specified apps: `install postgres`. The
   available apps are defined in `$ROOTapps/`, and have different build 
   configurations. This is up to the user to define and document.

