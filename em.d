static import std.stdio;
import std.internal.cstring : tempCString;
import std.getopt  : getopt;
import std.path    : CaseSensitive;
import std.format  : format;
import std.typecons: Flag, Yes, No;
import std.string  : indexOf;
import std.process : environment;

import common;

version(Windows)
{
    import core.sys.windows.windows :
        DWORD,
        ERROR_SUCCESS, ERROR_MORE_DATA,
        GetLastError,
        HKEY, HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER, KEY_QUERY_VALUE,
        REG_SZ, REG_EXPAND_SZ, REG_MULTI_SZ,
        RegOpenKeyExA, RegCloseKey, RegQueryValueExA;
}

version(Windows)
{
    enum PathCaseSensitive = CaseSensitive.no;
    enum MultiPathDelimiter = ';';
}
else
{
    enum PathCaseSensitive = CaseSensitive.yes;
    enum MultiPathDelimiter = ':';
}

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
        if(index > 0 && pathenv[index-1] != MultiPathDelimiter)
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
        if(c == MultiPathDelimiter)
        {
            return true;
        }
    }
}

void usage()
{
    mode.echo("Usage: em <command> <args>");
    mode.echo("");
    mode.echo("Common Commands:");
    mode.echo("  reset             Reset all environment variables to their initial values");
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

int main2(string[] args)
{
    {
        size_t newArgsLength = 0;
        for(size_t i = 0; i < args.length; i++)
        {
            auto arg = args[i];
            if(arg.length > 0 && arg[0] != '-')
            {
                args[newArgsLength++] = arg;
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
    if(command == "reset")
    {
        return resetCommand(args[1..$]);
    }
    else
    {
        mode.echof("Error: unknown command \"%s\"", command);
    }

    return 0;
}

int resetCommand(string[] args)
{
    if(args.length > 1)
    {
        mode.echof("Error: too many args for the 'reset' command");
        return 1;
    }

    version(Windows)
    {
        mode.echof("Error: path reset is not implemented on this platform");
        return 1;
    }
}

