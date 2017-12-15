static import std.stdio;
import std.getopt  : getopt;
import std.format  : format, formattedWrite;
import std.typecons: Flag, Yes, No;
import std.string  : indexOf;
import std.process : environment;
import std.array   : array, replace, Appender, appender;
import std.path    : dirName, buildPath, buildNormalizedPath, asNormalizedPath;
import std.file    : FileException, isFile, isDir, readText, thisExePath;

import common;

bool containsPath(inout(char)[] pathenv, inout(char)[] path)
{
    ptrdiff_t index = 0;
    while(true)
    {
        //writefln("index is %s", index);
        auto nextIndex = pathenv[index..$].indexOf(path, PathCaseSensitive);

        //writefln("nextIndex is %s", nextIndex);
        if(nextIndex < 0)
        {
            return false;
        }
        index += nextIndex;

        // Check that index is the start of a path
        if(index > 0 && pathenv[index-1] != MultiPathDelimiterChar)
        {
            index += path.length;
            continue;
        }

        // Check that it is the end of a path
        index += path.length;
        if(index >= pathenv.length)
        {
            return true;
        }
        auto c = pathenv[index];
        if(c == MultiPathDelimiterChar)
        {
            return true;
        }
    }
}

void usage()
{
    mode.echo("Usage: pm <command> <args>");
    mode.echo("");
    mode.echo("Commands:");
    mode.echo("  list [<pathspec>]   List the paths in <pathspec> (defaults to PATH)");
    mode.echo("  add <pathspec>      Add the given pathspec to PATH");
    mode.echo("  remove <path>       Remove <path> from PATH, exit code 0 whether or not it was removed");
    mode.echo("  reset               Reset PATH to the default");
    mode.echo("  break <program>     Break <program> by removing all paths that contain it");
    mode.echo("  diff <set1> <set2>  Print the changes to convert set1 to set2");
    mode.echo("");
    mode.echo("Pathset Commands:");
    mode.echo("  status            Prints the current status of path management");
    mode.echo("  enable <pathset>  Enable a pathset which adds all paths in the set to PATH");
    mode.echo("  disable <pathset> Disable a pathset which removes any pathes that were only referenced by this pathset");
    mode.echo("  reload            Reloads the pathset definitions and updates the PATH");
    mode.echo("");
    mode.echo("Advanced Commands:");
    mode.echo("  saveInitial          Save the initial path in the current environment.  Normally this");
    mode.echo("                       is done automatically when the path is going to be modified, this");
    mode.echo("                       command allows you to save it without modifying it. If the initial");
    mode.echo("                       path set has already been saved, this command does nothing.");
    mode.echo("  checkedRemove <path> Remove <path> from PATH, exit code 0 if it was removed, 1 if it");
    mode.echo("                       wasn't, and all other values indicate an error occurred");
    mode.echo("Options:");
    mode.echo("  -I <path>       Include a directory that contains pathset files.");
    mode.echo("  -back           Add the path(s) to the back of the set");
    mode.echo("  -front          Add the path(s) to the front of the set");
    mode.echo("");
    mode.echo("A \"pathspec\" is a \"path sepcifier\".  If it does not contain any path seperators, then");
    mode.echo("it's a path set name, otherwise, it's a single path.");
}

int main(string[] args)
{
    args = args[1..$];

    // This means the program is being run with a batch wrapper. Every
    // line of output from this program is interpretted as a batch command.
    if(args.length > 0 && args[0] == "batch")
    {
        mode = new BatchMode();
        args = args[1..$];
    }

    try
    {
        return main2(args);
    }
    catch(SilentExitException e)
    {
        return e.exitCode;
    }
    catch(Throwable e)
    {
        mode.echo(e.msg);
        return 1;
    }
}

__gshared Appender!(string[]) pathSetDirectories;
__gshared bool globalFrontOption = false;
__gshared bool globalBackOption = false;

int main2(string[] args)
{
    pathSetDirectories.put(buildNormalizedPath(dirName(thisExePath()), "pathsets"));

    {
        size_t newArgsLength = 0;
        for(size_t i = 0; i < args.length; i++)
        {
            auto arg = args[i];
            if(arg.length > 0 && arg[0] != '-')
            {
                args[newArgsLength++] = arg;
            }
            else if(arg == "-I")
            {
                i++;
                if(i >= args.length)
                {
                    mode.echof("Error: option -I requires an argument");
                    return 1;
                }
                auto pathSetDirectory = args[i];
                if(!isDir(pathSetDirectory))
                {
                    mode.echof("Error: \"%s\" is not a directory", pathSetDirectory);
                    return 1;
                }
                pathSetDirectories.put(cast(string)asNormalizedPath(pathSetDirectory).array);
            }
            else if(arg == "-front")
            {
                if(globalBackOption)
                {
                    mode.echof("Error: cannot specify both -front and -back");
                    return 1;
                }
                globalFrontOption = true;
            }
            else if(arg == "-back")
            {
                if(globalFrontOption)
                {
                    mode.echof("Error: cannot specify both -front and -back");
                    return 1;
                }
                globalBackOption = true;
            }
            else
            {
                mode.echof("Error: unknown option \"%s\"", arg);
                return 1;
            }
        }
        args = args[0..newArgsLength];
    }

    if(args.length == 0)
    {
        usage();
        return 0;
    }

    auto command = args[0];
    if(command == "list")
        return listCommand(args[1..$]);
    if(command == "reset")
        return resetCommand(args[1..$]);
    if(command == "diff")
        return diffCommand(args[1..$]);
    if(command == "add")
        return addCommand(args[1..$]);
    if(command == "remove")
        return removeCommand(args[1..$]);

    mode.echof("Error: unknown command \"%s\"", command);

    return 0;
}

int listCommand(string[] args)
{
    string path;
    if(args.length == 0)
    {
        path = environment["PATH"];
    }
    else
    {
        if(args.length > 1)
        {
            assert(0, "not implemented");
        }
        auto pathSetName = args[0];

        path = tryGetPathSet(pathSetName);
        if(path is null)
        {
            mode.echof("Error: unknown path-set \"%s\"", pathSetName);
            return 1;
        }
    }
    size_t index = 0;
    foreach(dir; pathIterator(path))
    {
        mode.echof("%s. %s", index, dir);
        index++;
    }
    return 0;
}

int resetCommand(string[] args)
{
    if(args.length > 1)
    {
        mode.echo("Error: too many args for the 'reset' command");
        return 1;
    }

    version(Windows)
    {
        mode.setPath(format("%s;%s",
            registryGetSystemEnv(CString("PATH\0")).
                expandFormat(&registryGetUserOrSystemEnvWithString),
            registryGetUserEnv(CString("PATH\0")).
                expandFormat(&registryGetUserOrSystemEnvWithString)));
        return 0;
    }
    else
    {
        mode.echof("Error: reset is not implemented on this platform");
        return 1;
    }
}

int diffCommand(string[] args)
{
    if(args.length != 2)
    {
        mode.echof("Error: diff command requires 2 pathsets");
        return 1;
    }
    auto pathSetName1 = args[0];
    auto pathSetName2 = args[1];

    // Todo: handle case sensitivity if path names are not case sensitive
    if(pathSetName1 == pathSetName2)
    {
        mode.echo("Cannot diff a path set with itself");
        return 1;
    }

    auto pathSet1 = tryGetPathSet(pathSetName1);
    if(pathSet1 is null)
    {
        mode.echof("Error: unknown path set \"%s\"", pathSetName1);
        return 1;
    }
    auto pathSet2 = tryGetPathSet(pathSetName2);
    if(pathSet2 is null)
    {
        mode.echof("Error: unknown path set \"%s\"", pathSetName2);
        return 1;
    }

    return DiffCode.diff(pathSet1, pathSet2);
}

int addCommand(string[] args)
{
    if(args.length == 2)
    {
        mode.echo("Error: the add command requires 1 or more arguments, either path set names or paths.");
        return 1;
    }

    auto PATH = environment.get("PATH", "");

    foreach(pathSpecifier; args)
    {
        if(pathSpecifier.containsPathSeparator())
        {
            PATH = addPath(PATH, pathSpecifier, "PATH");
        }
        else
        {
            auto pathSet = tryGetPathSet(pathSpecifier);
            if(pathSet is null)
            {
                mode.echof("Error: unknown path set \"%s\"", pathSpecifier);
                return 1;
            }
            foreach(path; pathIterator(pathSet))
            {
                PATH = addPath(PATH, path, "PATH");
            }
        }
    }

    mode.setPath(PATH);
    return 0;
}

// Returns: -1 if not a number
int tryParseNum(string str)
{
    int value = 0;
    foreach(c; str)
    {
        if(c > '9' || c < '0')
            return -1;
        value *= 10;
        value += c - '0';
    }
    return value;
}

int removeCommand(string[] args)
{
    if(args.length == 0)
    {
        mode.echo("Error: the 'remove' command requires 1 or more arguments");
        return 1;
    }

    char[] PATH = environment.get("PATH", "").dup;
    auto pathNumsToRemove = appender!(int[])();
    bool removedPathString = false;
    foreach(arg; args)
    {
        auto pathNum = tryParseNum(arg);
        if(-1 != pathNum)
        {
            if(removedPathString)
            {
                mode.echo("Error: cannot mix removing path numbers and strings");
                return 1;
            }
            pathNumsToRemove.put(pathNum);
        }
        else
        {
            if(pathNumsToRemove.data.length > 0)
            {
                mode.echo("Error: cannot mix removing path numbers and strings");
                return 1;
            }
            removedPathString = true;
            mode.echo("Error: removing string paths not implemented");
            return 1;
        }
    }

    if(pathNumsToRemove.data.length > 0)
    {
        // need to sort path nums so when the path gets modified, the
        // path nums are still valid
        import std.algorithm : sort;
        sort!"a > b"(pathNumsToRemove.data);

        static struct RemovedPaths
        {
            string[] paths;
            size_t next;
            this(size_t size)
            {
                this.paths = new string[size];
                this.next = 0;
            };
            void onPathRemoved(const(char)[] path)
            {
                assert(next < paths.length);
                paths[next++] = path.idup;
            }
        }
        auto removed = RemovedPaths(pathNumsToRemove.data.length);

        foreach(num; pathNumsToRemove.data)
        {
            if(!tryRemovePathInPlace(&PATH, num, &removed))
            {
                mode.echof("Error: failed to remove path %s", num);
                return 1;
            }
        }
        assert(removed.next == pathNumsToRemove.data.length, "code bug");
        foreach(i, num; pathNumsToRemove.data)
        {
            mode.echof("Removed %s. %s", num, removed.paths[i]);
        }
    }

    mode.setPath(PATH);
    return 0;
}

string addPath(string pathSet, string newPath, string setNameLog)
{
    size_t matchingIndex;
    size_t index = 0;
    foreach(path; pathIterator(pathSet))
    {
        if(pathsAreTheSame(path, newPath))
        {
            matchingIndex = index;
            goto MATCH_FOUND;
        }
        index++;
    }

    if(globalBackOption)
    {
        if(setNameLog)
        {
            mode.echof("Adding \"%s\" to back of %s", newPath, setNameLog);
        }
        return buildPathSet(pathSet, newPath);
    }
    if(setNameLog)
    {
        mode.echof("Adding \"%s\" to front of %s", newPath, setNameLog);
    }
    return buildPathSet(newPath, pathSet);

  MATCH_FOUND:
    if(globalBackOption)
    {
        assert(0, "not implemented");
    }
    else if(globalFrontOption)
    {
        assert(0, "not implemented");
    }
    else
    {
        if(setNameLog)
        {
            mode.echof("Path \"%s\" already exists in %s", newPath, setNameLog);
        }
        return pathSet;
    }
}

auto buildPathSet(inout(char)[] left, inout(char)[] right)
{
    if(left.length == 0)
    {
        return right;
    }
    if(right.length == 0)
    {
        return left;
    }
    if(left[$-1] == MultiPathDelimiterChar)
    {
        if(right[0] == MultiPathDelimiterChar)
        {
            return left ~ right[1..$];
        }
        else
        {
            return left ~ right;
        }
    }
    else
    {
        if(right[0] == MultiPathDelimiterChar)
        {
            return left ~ right;
        }
        else
        {
            return cast(inout(char)[])(left ~ MultiPathDelimiterString ~ right);
        }
    }

}

// Returns true if the two paths have the same "meaning".  This means
// this could be the same even if the exact characters don't match completely.
bool pathsAreTheSame(const(char)[] path1, const(char)[] path2)
{
    // TOOD: make this work regardless of the exact characters in each path
    return path1 == path2;
}

struct DiffCode
{
    static int diff(T)(T pathSet1String, T pathSet2String)
    {
        auto pathSet1 = PathSet(pathSet1String);
        auto pathSet2 = PathSet(pathSet2String);

        DiffState state;

        diff(&state, pathSet1, pathSet2);

        foreach(diffNode; state.diffNodes.data)
        {
            final switch(diffNode.diffType)
            {
              case DiffType.passThrough:
                mode.echof("  %s", diffNode.targetNode.path);
                break;
              case DiffType.add:
                mode.echof("+ %s", diffNode.targetNode.path);
                break;
              case DiffType.move:
                // For now, the '/' character means the path was moved up in priority from the original set
                mode.echof("/ %s", /*diffNode.originalNode.index, diffNode.targetNode.index, */diffNode.targetNode.path);
                break;
              case DiffType.remove:
                mode.echof("- %s", diffNode.originalNode.path);
                break;
            }
        }

        return 0;
    }

    static struct PathNode
    {
        size_t index;
        string path;
        bool samePathAs(PathNode other)
        {
            return pathsAreTheSame(this.path, other.path);
        }
        void toString(scope void delegate(const(char)[]) sink) const
        {
            formattedWrite(sink, "%s(%s)", path, index);
        }
    }
    static struct PathSet
    {
        PathNode* nodes;
        PathNode* limit;

        this(string setString)
        {
            auto appender = appender!(PathNode[])();
            size_t index = 0;
            foreach(path; pathIterator(setString))
            {
                appender.put(PathNode(index, path));
                index++;
            }
            this.nodes = appender.data.ptr;
            this.limit = appender.data.ptr + appender.data.length;
        }

        @property bool empty() { return nodes == limit; }
        @property PathNode next() in { assert(nodes != limit); }
            body { return *nodes; }
        void popFront()
        {
            nodes++;
        }
        auto findAndRemove(PathNode node)
        {
            PathNode match = void;
            PathNode* next;
            for(next = nodes; next < limit; next++)
            {
                if(next.samePathAs(node))
                {
                    match = *next;
                    goto REMOVE_MATCH;
                }
            }

            return PathNode(0, null);

          REMOVE_MATCH:
            for(;;next++)
            {
                auto copyFrom = next + 1;
                if(copyFrom >= limit)
                {
                    break;
                }
                *next = *copyFrom;
                next++;
            }
            limit--;
            return match;
        }
        bool contains(PathNode node)
        {
            for(auto next = nodes; next < limit; next++)
            {
                if(next.samePathAs(node))
                {
                    return true;
                }
            }
            return false;
        }
    }

    enum DiffType
    {
      passThrough,
      add,
      move,
      remove,
    }
    static struct DiffNode
    {
        DiffType diffType;
        PathNode originalNode;
        PathNode targetNode;
    }
    static struct DiffState
    {
        Appender!(DiffNode[]) diffNodes;
        size_t nextExpectedTargetIndex;
        void emitPassThrough(PathNode originalNode, PathNode targetNode)
        {
            assert(targetNode.index == nextExpectedTargetIndex);
            nextExpectedTargetIndex++;

            //mode.echof("emitPassThrough %s %s", originalNode, targetNode);
            diffNodes.put(DiffNode(DiffType.passThrough, originalNode, targetNode));
        }
        void emitAdd(PathNode node)
        {
            assert(node.index == nextExpectedTargetIndex);
            nextExpectedTargetIndex++;

            //mode.echof("emitAdd %s", node);
            diffNodes.put(DiffNode(DiffType.add, PathNode(0, null), node));
        }
        void emitMove(PathNode originalNode, PathNode targetNode)
        {
            assert(targetNode.index == nextExpectedTargetIndex);
            nextExpectedTargetIndex++;

            //mode.echof("emitMove %s %s", originalNode, targetNode);
            diffNodes.put(DiffNode(DiffType.move, originalNode, targetNode));
        }
        void emitRemove(PathNode node)
        {
            //mode.echof("emitRemove %s", node);
            diffNodes.put(DiffNode(DiffType.remove, node));
        }
    }
    static void diff(T,U)(T state, U originalSet, U targetSet)
    {
        for(;;)
        {
            if(originalSet.empty)
            {
                for(auto next = targetSet.nodes; next < targetSet.limit; next++)
                {
                    state.emitAdd(*next);
                }
                break;
            }
            if(targetSet.empty)
            {
                for(auto next = originalSet.nodes; next < originalSet.limit; next++)
                {
                    state.emitRemove(*next);
                }
                break;
            }

            if(targetSet.next.samePathAs(originalSet.next))
            {
                state.emitPassThrough(originalSet.next, targetSet.next);
                originalSet.popFront();
                targetSet.popFront();
                continue;
            }

            if(!targetSet.contains(originalSet.next))
            {
                state.emitRemove(originalSet.next);
                originalSet.popFront();
                continue;
            }

            auto match = originalSet.findAndRemove(targetSet.next);
            if(!match.path)
            {
                state.emitAdd(targetSet.next);
                targetSet.popFront();
                continue;
            }

            state.emitMove(match, targetSet.next);
            targetSet.popFront();
        }
    }
}

auto spaces(T)(T count)
{
    static struct Formatter
    {
        T count;
        this(T count) { this.count = count; }
        void toString(scope void delegate(const(char)[]) sink) const
        {
            foreach(i; 0..count)
            {
                sink(" ");
            }
        }
    }
    return Formatter(count);
}

auto tryGetPathSet(const(char)[] name)
{
    // handle special path sets
    if(name == "path")
    {
        return environment.get("PATH", null);
    }

    version(Windows)
    {
        if(name == "windows_sys")
        {
            return format("%s", registryGetSystemEnv(CString("PATH\0")).
                expandFormat(&registryGetUserOrSystemEnvWithString));
        }
        if(name == "windows_user")
        {
            return format("%s", registryGetUserEnv(CString("PATH\0")).
                expandFormat(&registryGetUserOrSystemEnvWithString));
        }
        if(name == "windows")
        {
            return format("%s;%s",
                registryGetSystemEnv(CString("PATH\0")).
                    expandFormat(&registryGetUserOrSystemEnvWithString),
                registryGetUserEnv(CString("PATH\0")).
                    expandFormat(&registryGetUserOrSystemEnvWithString));
        }
    }

    // read in the path sets
    foreach(pathSetDirectory; pathSetDirectories.data)
    {
        auto pathSetFilename = buildPath(pathSetDirectory, name);
        bool isFileResult = false;
        try
        {
            isFileResult = isFile(pathSetFilename);
        }
        catch(FileException e)
        {
            continue;
        }
        if(isFileResult)
        {
            return readText(pathSetFilename).
                replace("\r\n", MultiPathDelimiterString).
                replace("\n", MultiPathDelimiterString).
                replace(MultiPathDelimiterString~MultiPathDelimiterString, MultiPathDelimiterString);
        }
    }

    return null;
}
