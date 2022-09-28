# Install Utility
This repository provides a bash/ssh-based utility for practically scaffolding
a provisioning and/or deployment configuration.

## Setting up
### Interactive shell

You can execute `shell.sh` to run an interactive shell. This will assume
the `ROOT` variable will point to your project's root. Create a file
`shell.sh` as such:

```
#!/bin/bash

ROOT="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"
env ROOT=$ROOT $ROOT/install-util/shell.sh
```

And invoke it from your command line:

```
./shell.sh
```

### Command-line script

To use any of the util functions (such as `install`), you would include
the rc.sh and declare the ENV variable in a script called `install.sh`:
```
#!/bin/bash

set -eu

ROOT="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"
ENV="$1"
shift
source $ROOT/install-util/rc.sh

install $@
```

Calling the script from the shell with arguments will try to install one or
more applications directly:

```
./install.sh testing mysql redis
```

### `config.json`
The only required section required in config.json is `deployments`. This
specifies which ssh server connection should be used for what app. If the
environment is identical to the server name, it can be specified as "*":

```
{
    "deployments": {
        "postgres": {
            "prod": "root@example.org"
        },
	"deps": "*"
    }
}
```

### `ssh/config`
This is a `ssh_config` file that may contain all servers used in the deployments
configuration. Also, it is advisable to add control socket configuration to this 
file to avoid needless reconnecting during installation/deployment:

```
Host *
  ControlMaster auto
  ControlPath=/tmp/zorgverkeer-%C
  ControlPersist 300
  ServerAliveInterval 10
```

### Project configuration
The `project.sh` file is used to declare global project-specific variables that
can be used in the build script. If the variables are needed in the install
scripts as well, they need to be declared in the `build_vars` variable.

The file may also provide bash functions that can be invoked by the build-script.

At the very least, it should provide a 'NAMESPACE' variable:

```
export NAMESPACE="my-project"
```

### Generic app configuration
The `vars.sh` file is used to declare variables for each app. This is typically
used to read configuration from the config.json file based on the `$ENV` and 
`$app` variables. This would include information such as docker networking.

## Apps
The `$ROOT/apps/` directory contains the applications that can be installed on
servers, either as a dependency for other apps or as part of the provisioning.
Refer to each of the README files in their respective app folder for
app-specific documentation.

Generally speaking, installing an app will follow these steps:

1. The file `install.sh` in the `apps/$APPNAME` directory is checked. If it
   doesn't exist, it is considered an invalid app name and the script exits.
2. The server to connect to is looked up using the `deployments` section of
   `config.json`. If the server is called "local", the local shell is used to execute 
   commands, otherwise, it is assumed to be a valid designation for use in calls
   to SSH. If the deployment is not configured, the script exits with an error
   message. Each server name corresponds to an SSH Host section, as configured in
   `ssh/config`.
3. If there is also a build.sh present, an `artifacts` directory is created within
   the app directory, with the selected environment as a subdirectoy. The full path
   to this directory is assigned to the `$artifacts` variable for use in the build.sh
   script.
4. Subsequently, the build script is invoked. Available variables are `$ENV`, `$app`,
   `$resources` (pointing to the app's resources directory, if it exists) and whatever
   variables are exported by the `vars.sh` file. The `build_vars` variable is used
   to indicate to the install script which variables can be propagated to the install
   script. See the 'Variables' section below for the available variables.
5. If there are resources and/or artifacts, an SSH connection to the relevant server
   is opened and files are rsync'd to `~/$app/$ENV/resources` and `~/$app/$ENV/artifacts`
   respectively. The variables `$resources` and `$artifacts` pointing to the remote
   equivalent are updated accordingly. 
6. A env-specific install script is generated by declaring all the vars indicated by
   the `$build_vars` variable. Additionally the `install.sh` script is added.
7. The newly generated env-specific install script is fed to a shell opened on
   the SSH server, or executed by the local shell if the deployment indicates such.

### Variables
The following variables are available to all build and install scripts:

- `$ENV` - The current target environment. This is the app's deployment environment, e.g. 'production'.
- `$NAMESPACE` - The project's namespace, useful for prefixing. This is declared in project.sh
- `$app` - The name of the app that is currently being installed.
- `$server` - The server name that is used for deployment.
- `$resources` - a full path to the resources directory of the app. In `build.sh` this refers to the 
   local directory; in `install.sh` this refers to the rsync'd remote. Note that it remains empty if no 
   `build.sh` exists.
- `$artifacts` - a full path to the artifacts directory for the current environment of the app. The path
  handling difference between `build.sh` and `install.sh` locally and remotely is the same as for resources.

All variables exported from the `build_vars` variable are expanded too. Note that this variable can be
amended on a per-app per-deployment basis in the `vars.sh` file.

### Debugging
While creating new apps, it is advisable to enable debugging at level 2 or higher
as long as the script is still in development:

```
DEBUG=2 ./install.sh testing mysql redis
```

This will ultimately print the script that would otherwise be executed on
the configured server. `DEBUG=1` will only output a lot of tracing information
but will do the ultimate installation on the remote.

DEBUG=3 will print the resulting installation script using `envsubst` which
tries to expand as much of the variables in the script as possible. This is
useful to easily spot escape and/or quoting errors. Note that this isn't 
exactly the way bash works, so it should only be used as a means of debugging
and inspection.

### Application-specifics

Some applications may need a VERSION which needs to be installed. An
environment variable is used for this:

```
VERSION="the-version" ./install.sh the-env the-app
```

Typically, a version would correspond to a docker image tag, but this
is up to the application install script itself.

### Shell usage

Running the shell will show a prompt:

```
namespace [development] 
```

This means that any install command executed here will be executed on the
development environment. If you wish to install a local instance of the
`postgres` app, you would type:

```
install postgres
```

This will trigger the build/install sequence of the `postgres` 
app on the local environment.

If you wish to switch to another environment, you type

```
env other-environment
```
Which would the result in a new prompt:

```
namespace [other-environment]
```

Executing the installation of `postgres` now, would look up the postgres app in
the `deployments` section of `config.json` and connect to the server associated
with that deployment:

```
install postgres
```

## Robustness
All scripts are executed within a `set -euo pipefail` bash shell. This means
that any command invoked that results in an error is considered a failing script.

### Error codes
If you would use a subshell command substitution, the error code of that shell
is lost when used directly in a string, or in a `local` declaration. It is
therefore better to always declare variables for such substitutions so the
error codes are interpreted correctly. 

For example:
```
# Don't do this:
local var="$(_my_helper_func "$ENV" "$app")
# But do this:
local var; var="$(_my_helper_func "$ENV" "$app")

# Don't do this:
echo "$(do_something) $(do_something_else)"
# But do this:
var1="$(do_something)"
var2="$(do_something_else)"
echo "$var1 $var2"
```

### Undefined variables
If variables may or may not be available, it is prudent to always provide
a default value. It's best to declare these as early as possible:

```
my_var="${my_var:-"the default value"}"
```

### Using the config.json
The `jq` tool is used to read values from the config. It is up to you to
structure the config any way you like, except for the `deployments` section.

Accessing values that are non-existent is not necessarily considered an error.
This means that you need to do your own error checking, for example:

```
local ip; ip="$(_cfg_get ip $app)"
! test -z $ip;
```
