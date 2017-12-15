em (Environment Manager)
================================================
Manages environment variables.


pm (Path Manager)
================================================
Manages the PATH environment variable.

Reset PATH to the default initial value:
```
pm reset
```

Add/Remove a single path or a named set of paths (`<pathspec>`)
```
pm add <pathspec>
pm remove <pathspec>
```

Print the difference between two path sets
```
pm diff <pathset1> <pathset2>
```

How to Build/Install on Windows
------------------------------------------------
Using the D-Compiler, run the `build.bat` script.  This should produce the "pmExe.exe" file.  Copy this along with the existing "pm.bat" file to a directory in your PATH.

Problems and Solutions
------------------------------------------------

#### Problem
Reset the current console to the default PATH
#### Solution
```
pm reset
```
On windows this will read the registry settings for the PATH environment variable for both the system and the current user.  It puts the system paths before the user path.

Not sure how to accomplish this on other operating systems yet.


#### Problem
Add a set of predefined paths to the current console.
#### Solution
"Path sets" allow you to assign a name to a set of paths and they can be added to the current console using:
```
pm add <pathset>
```
The pathsets are stored in the a directory called "pathsets" in the same directory as the "pm" executable.  Each path set is stored as a file where the name of the pathset is the name of the file. The format of the pathset files is simply one path per line.


#### Problem
Editing the default system/user paths
#### Solution
This is not implemented yet but I imagine on windows you could do something like this
```batch
:: Add default paths for the whole system
pm setadd windows_system <pathspec>...
:: Add default paths for current the user
pm setadd windows_user <pathspec>...
```
The `windows_system` and `windows_user` are special path sets that represent the default initial PATH stored in the registry.  They should behave just like normal path sets which means they should also be "modifiable" using the "setadd" command.


#### Problem
List the current default PATH in a platform independent way and make it easy to read.
#### Solution
```
pm list <pathset>
```
This command will list the contents of any path set, one path per line.  Since the default initial PATH should also be a path set (not sure on the name yet) you can leverage the "list" command to print it in an easy to read format.

#### Problem
Path sets (like the default system/user PATHs on windows) contain duplicate paths, non-existent paths or paths may have an inconsistent style/format.
#### Solution
```batch
:: clean all path sets
pm clean *

:: clean the given pathsets
pm clean <pathset>...

:: options
pm clean [-ignore-missing] [-ignore-duplicates] [-ignore-style]
```
The `clean` command will cleanup the given path sets by removing duplicate paths, non-existent paths and normalizing the style of all paths.


### Ideas

Break `<program>` by removing all paths that contain it:
```
pm break <program>
```

Find and print all paths containig a `<program>`:
```
pm find <program>
```

On Windows there are 2 special path sets, system and user.  The path program treats these sets specially like knowing how to modify them so they are persistent.
The "system" path set is the path set defined by the system

Managing the system path settings
```
pm list s
```


Reset the PATH to the default
```
pm reset
```

List all of the paths
```
pm list
```


A stack of path operations
```
pm pop # Undo the previous push command (even if the last push command did nothing)

pm push <pathspec>...
pm push /usr/bin  # Adds a single path
pm push buildllvm # Adds all paths in the buildllvm path set
```





### Path Sets

A "path set" is a named set of paths. The `path` program can enable/disable path sets in the current environment. There are 2 special path sets, the "initial" set and the "manual" set.  The "initial" set is the set of paths that were set before the `path` program made any modifications. The "manual" path set is the set of all the paths that have been manually added using the "add" command in the current session.

The "path" program keeps track of all the currently enabled path sets.  When a path set is disabled, the path program will check all the paths in that path set to see if any other set still holds a reference to that path, if so, the path remains in the PATH, otherwise, it is removed from the PATH.

When a path is removed manually using the "remove" command, this can also affect the current path sets.  If a path from a path set is removed, then that pathset has become broken.


# Idea
Maybe try modeling the `pm` program after git.  I could track changes/commit/add/remove/etc.

# Idea
Figure out how to handle path order.

Maybe by default all paths are added to the front?  If you want to add it to the back you use an option like `-back`?

Add advanced commands to check for duplicate programs in multiple paths.

I think the remove command would intuitively do whatever it had to in order to remove the given path from the PATH.

The should be another variant of the remove command that removes a path from a currently applied path set. Maybe, path unlink <set> <path>. This could would only remove the path from the PATH if no other sets contained that path.


# Idea
I think a good definition for PATH would be the union of all the path sets then taking out all the paths in the filter.

Instead of path remove, a better version might be "path filter".  This is a manual set that acts as a filter. You could also apply path sets as filters instead of unions!

So to calculate the PATH, you take the ordered union of all the enabled path sets, then you remove all the paths in the filter path sets.

Special sets.

initial, added and filtered

Note the added and filtered set are related. They are mutually exclusive so a path cannot exist in both.

# Idea

Maybe the remove command should fail if that path exists in an enabled path set other than initial or manual.

# Idea

pm filterset cmake

# Idea
```
pm append ...
pm appendset ...

pm push ...
pm pushset ...
```
OR
```
pm add [-f] ...
pm addset [-f] ...
-f means add in front

pm filter ...
pm filterset...

filter will remove the path from the manual set.

pm removeset...
```
# Idea
```
pm add -s llvm /llvm/bin
```
Adds to the path and the llvm set.

# Idea
```
pm list # lists the paths in order with number you can use to remove or insert using an integer
pm insert <index> paths
pm save <name>
pm load <name>
```
# Idea

Maybe path sets should just be files with paths on each line. And they could #incude <pathset>

# Idea
```
pm commit
vcvarsall.bat
pm diff
```
See what has changed with the path

# Idea

Have a way to put in generic paths that may not go into the PATH but can be searched for programs.

# Idea
Register a path that contains programs.
```
pm register <path>
```
