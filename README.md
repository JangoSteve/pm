# Redmine PM (Project Management) CLI

This is a command line utility for doing project management with Redmine
in Bash. It is written completely in Bash.

## Dependencies

This has been tested with Bash v3.2 and should work with anything
greater as well. The only dependency is JQ, which can be installed on
Mac via Homebrew with:

```
brew install jq
```

## Installation

Git clone this repo or copy the `pm.sh` file somehwere onto your
computer, and then make sure that its directory is in your shell
environment's `$PATH`.

I've done this on my computer by creating a `bin` folder in my home
directory, then symlinking the utility like so:

```
mkdir -p ~/bin
ln -s /full/path/to/pm/pm.sh ~/bin/pm
```

And then adding this to `~/.bash_profile`:

```
export PATH="~/bin:$PATH"
```

## Configuration

The utility is made to access data in Redmine on a per-project basis.
For convenience, you can configure your different project directories on
your computer to access different projects on Redmine (or even different
instances of Redmine) when you are running the `pm` command from within
those directories.

To do this, create a `.redmine` file in your project's working
directory, and provide it with your Redmine access credentials and
default configuration. See the `.redmine.sample` file for an example
configuration.

In this file, these are the available configurations:

### Per Redmine Instance

* `API_KEY`: Your Redmine API key.
* `DOMAIN`: The domain of the Redmine instance with which you wish to
  interact.

### Per Project

* `PROJECT_ID`: The numeric project ID of the project with which the
  working directory corresponds.
* `CURRENT_VERSION_ID`: If you're using Redmine "Versions" (aka "Target
  Version" or "Fixed Version") to manage your sprints, this is useful to
set the default target version for listing Issues.

## Using

General usage is of the form:

```
pm [flags] function [secondary function] [arguments]
```

Where the parts in `[]` are optional. The simplest valid command is:

```
pm function
```

Some functions require inputs which can be passed either via
`[arguments]` or may also be piped into `pm`.

Use `pm -h` for a list of available `[flags]`.

NOTE: If running with any `[flags]`, the `[flags]` must come before the `function`.

Here are the available functions and secondary functions:

* `project`: Get the configured Project for the current working
  directory. Can override Project to get with `-p` flag.
* `queries`: Get the Saved Queries for Project.
* `statuses`: Get the available Statuses for querying and updating Issues.
* `categories`: Get the available Categories for querying and updating Issues.
* `users`: Get the available Users for querying and updating Issues.
* `user`: Get the current user.
* `versions`: Get the available Versions for querying and updating
  Issues. Format of output can be specifies with `-f` flag.
* `versions update`: Update a Version. Use the `-c true` flag with a
  quoted JSON object to specify the attributes to update.
* `issue`: Get Issue information. Pass Issue ID as argument (or piped in).
* `issue open`: Open Issue in browser. Pass Issue ID as argument (or
  piped in).
* `issue update`: Update Issue using `-c true` with quoted JSON object
  to specify the attributes to update.
* `issues`: List multiple Issues. Pass space-separated Issue IDs as
  arguments, or newline-separated issues piped in. You can also query
via `-q`, `-v`, `-a`, or `-c true` custom query with JSON.
* `issues update`: Update multiple Issues using `c true` with quoted
  JSON object to specify the attributes to update. The Issue IDs to
update need to be passed in as space-separated arguments, or
newline-separated issues piped in.
* `issues open`: Open multiple Issues in the browser. Pass
  space-separated Issue IDs as arguments, or newline-separated issues
piped in. You can also query via `-q`, `-v`, `-a`, or `-c true` custom
query with JSON.

One thing to note about the above is that since arguments can be piped
in, you can combine multiple calls to `pm` by piping the output of one
call to the input of the next. For example, you can pipe the Issue IDs
from a custom Issue
query to the Issue update command.

This example does a custom query for Issues from Target Version 15
assigned to my user ID and created after January 15th, 2020, and updates
them with Status ID 5. Note that we format the output of the first
command to output IDs only (`-f ids`) and also silence any progress output
statements (`-z true`) so that they don't get piped in as Issue ID inputs to the
second command:

```
pm -v 15 -f ids -z true -c true issues '{"assigned_to_id": 3, "created_on": ">=2020-01-15"}' | pm -c true issues update '{"status_id": 5}'
```

Some other example commands:


```
pm -f ids -z true issues 8191 8338 | pm -f summary issues
```
```
pm -c true -f summary issues '{"created_on": ">=2019-10-01", "fixed_version_id": "!249"}'
```
```
pm -c true -f summary -z true issues '{"created_on": "lw"}' | sort
```
```
pm issue open 7784
```
```
pm versions
```
```
pm queries
```
```
pm -v 250 issues
```
