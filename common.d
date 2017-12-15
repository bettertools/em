module common;

static import std.stdio;
import std.internal.cstring : tempCString;
import std.format : format;
import std.path    : CaseSensitive;

version(Windows)
{
    import core.sys.windows.windows :
        DWORD,
        ERROR_SUCCESS, ERROR_FILE_NOT_FOUND, ERROR_MORE_DATA,
        GetLastError,
        HKEY, HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER, KEY_QUERY_VALUE,
        REG_NONE, REG_SZ, REG_EXPAND_SZ, REG_MULTI_SZ,
        RegOpenKeyExA, RegCloseKey, RegQueryValueExA;
}

version(Windows)
{
    enum PathCaseSensitive = CaseSensitive.no;
    enum MultiPathDelimiterChar   = ';';
    enum MultiPathDelimiterString = ";";
}
else
{
    enum PathCaseSensitive = CaseSensitive.yes;
    enum MultiPathDelimiterChar   = ':';
    enum MultiPathDelimiterString = ":";
}

// TODO: wrap asserts and exceptions so their result gets printed correctly (using mode.echo)
class SilentExitException : Exception
{
    int exitCode;
    this(int exitCode = 1)
    {
        super(null);
        this.exitCode = exitCode;
    }
}

class Mode
{
    //abstract bool isDefault();
    abstract void echo(const(char)[] msg);
    void echof(T...)(string fmt, T args)
    {
        echo(format(fmt, args));
    }
    abstract void setPath(const(char)[] path);
}

__gshared Mode mode = new DefaultMode();
class DefaultMode : Mode
{
    //override bool isDefault() { return true; }
    override void echo(const(char)[] msg)
    {
        std.stdio.writeln(msg);
    }
    override void setPath(const(char)[] path)
    {
        assert(0, "setPath not implemented in this mode");
    }
}
class BatchMode : Mode
{
    //override bool isDefault() { return false; }
    override void echo(const(char)[] msg)
    {
        // TODO: handle newlines properly
        if(msg.length == 0)
        {
            std.stdio.writeln("echo.");
        }
        else
        {
            std.stdio.writefln("echo %s", msg);
        }
    }
    override void setPath(const(char)[] path)
    {
        std.stdio.writefln("set PATH=%s", path);
    }
}

auto pathIterator(T)(T[] paths)
{
    return PathIterator!T(paths);
}
struct PathIterator(T)
{
    T* limit;
    T* current;
    size_t currentLength;
    this(T[] paths)
    {
        this.limit = paths.ptr + paths.length;
        this.current = paths.ptr - 1; // subtract 1 so popFront works correctly
        this.currentLength = 0;
        popFront();
    }
    @property bool empty() const
    {
        return current >= limit;
    }
    T[] front() const
    {
        return current[0..currentLength];
    }
    void popFront()
    {
        current += currentLength;
        if(current < limit)
        {
            current++; // skip delimiter
            for(auto next = current;; next++)
            {
                if(next == limit || *next == MultiPathDelimiterChar)
                {
                    currentLength = next - current;
                    break;
                }
            }
        }
    }
}
unittest
{
    void test(string paths, string[] expected...)
    {
        size_t index = 0;
        foreach(dir; pathIterator(paths))
        {
            assert(expected[index] == dir);
            index++;
        }
        assert(index == expected.length);
    }

    alias SEP = MultiPathDelimiterString;
    test("");
    test("a", "a");
    test("abc", "abc");
    test("a b c d", "a b c d");
    test("a b"~SEP~"c d", "a b", "c d");
    test("a b"~SEP~"c d"~SEP, "a b", "c d");
    test(SEP~"a b"~SEP~"c d"~SEP, "", "a b", "c d");
    test(SEP~"a b"~SEP~SEP~"c d"~SEP, "", "a b", "", "c d");
    version(Windows)
    {
        test(`C:\a b;D:\another;;\some path;/windows;/with space/ again`,
            `C:\a b`, `D:\another`, ``, `\some path`, `/windows`, `/with space/ again`);
    }
}

/** Returns a pointer to the first occurence of $(D c).  If no $(D c) is found
    then the limit is returned.
 */
private inout(char)* findCharPtr(inout(char)* str, const(char)* limit, char c)
{
    for(;;str++) {
        if(str >= limit || *str == c) {
           return str;
        }
    }
}

private struct NullRemoveHook
{
    pragma(inline) static void onPathRemoved(const(char)[] path) { }
}

// Returns: false if the pathIndex was too large
pragma(inline) bool tryRemovePathInPlace(T)(char[]* path, size_t pathIndex, T removeHook)
{
    auto limit = (*path).ptr + (*path).length;
    auto newLimit = tryRemovePathInPlace!T((*path).ptr, limit, pathIndex, removeHook);
    if(newLimit == limit)
    {
        return false; // fail
    }
    *path = (*path).ptr[0 .. newLimit - (*path).ptr];
    return true; // success
}
// Returns: new limit (if pathIndex is too big, returns original limit)
char* tryRemovePathInPlace(T)(char* path, char* limit, size_t pathIndex, T removeHook)
{
    const initialPath = path;
    for(;pathIndex > 0; pathIndex--)
    {
        path = path.findCharPtr(limit, MultiPathDelimiterChar);
        if(path == limit)
            return limit; // fail
        path++; // move past delimiter
    }

    auto end = path.findCharPtr(limit, MultiPathDelimiterChar);
    if(end == path)
        return limit; // fail

    if(end >= limit)
    {
        removeHook.onPathRemoved(path[0.. end - path]);
        return path - ((path > initialPath) ? 1 : 0);
    }

    removeHook.onPathRemoved(path[0 .. end - path]);
    end++;
    auto moveSize = limit - end;

    import core.stdc.string : memmove;
    memmove(path, end, moveSize);
    return path + moveSize;
}
unittest
{
    static void testbad(string str, size_t removeIndex)
    {
        import std.stdio; writefln("testbad '%s'", str);
        char[] modifiable = str.dup;
        assert(!tryRemovePathInPlace(&modifiable, removeIndex, NullRemoveHook()));
    }
    static void test(string str, size_t removeIndex, string expectedRemoved, string expectedAfter)
    {
        struct RemoveHookForTest
        {
            void onPathRemoved(const(char)[] removed)
            {
                assert(removed == expectedRemoved);
            }
        }
        import std.stdio; writefln("test '%s' (%s)", str, removeIndex);
        char[] modifiable = str.dup;
        assert(tryRemovePathInPlace(&modifiable, removeIndex, RemoveHookForTest()));
        assert(modifiable == expectedAfter);
    }
    alias SEP = MultiPathDelimiterString;

    testbad(null, 0);
    testbad(  "", 0);

    test   (  "a", 0, "a", "");
    testbad(  "a", 1);

    test   ("a"~SEP    , 0, "a", "");
    testbad("a"~SEP    , 1);

    test   ("a"~SEP~"b", 0, "a", "b");
    test   ("a"~SEP~"b", 1, "b", "a");
    testbad("a"~SEP~"b", 2);

    test   ("a"~SEP~"b"~SEP, 0, "a", "b"~SEP);
    test   ("a"~SEP~"b"~SEP, 1, "b", "a"~SEP);
    testbad("a"~SEP~"b"~SEP, 2);

    test   ("a"~SEP~"b"~SEP~"c", 0, "a", "b"~SEP~"c");
    test   ("a"~SEP~"b"~SEP~"c", 1, "b", "a"~SEP~"c");
    test   ("a"~SEP~"b"~SEP~"c", 2, "c", "a"~SEP~"b");
    testbad("a"~SEP~"b"~SEP~"c", 3);
}

struct CString
{
    const(char)[] str;
    this(const(char)[] str)
    {
        assert(str.ptr[str.length - 1] == '\0');
        this.str = str[0..$-1];
    }
    this(string str) immutable
    {
        assert(str.ptr[str.length - 1] == '\0');
        this.str = str[0..$-1];
    }
    @property auto ptr() inout { return str.ptr; }
    @property auto length() inout { return str.length; }
    @property auto slice() inout { return str; }
}


version(Windows)
{
    bool containsPathSeparator(const(char)[] path)
    {
        foreach(c; path)
        {
            if(c == '\\' || c == '/')
            {
                return true;
            }
        }
        return false;
    }
    struct RegistryData
    {
        DWORD type;
        ubyte[] bytes;
    }
    RegistryData tryReadData(HKEY key, CString name, size_t dataPadding = 0)
    {
        DWORD dataSize = 0;
        {
            DWORD type;
            auto errorCode = RegQueryValueExA(key, name.ptr, null, &type, null, &dataSize);
            if(errorCode != ERROR_SUCCESS)
            {
                if(errorCode == ERROR_FILE_NOT_FOUND)
                {
                    return RegistryData(REG_NONE, null);
                }
                // TODO: use FormatMessage to get a description
                mode.echof("Error: RegQueryValueExA to get size failed (e=%s)", errorCode);
                throw new SilentExitException();
            }
        }

        ubyte[] data;
        for(;;)
        {
            data = new ubyte[dataSize + dataPadding];
            DWORD type;
            auto errorCode = RegQueryValueExA(key, name.ptr, null, &type, data.ptr, &dataSize);
            if(errorCode == ERROR_SUCCESS)
            {
                return RegistryData(type, data);
            }
            if(errorCode != ERROR_MORE_DATA)
            {
                // TODO: use FormatMessage to get a description
                mode.echof("Error: RegQueryValueExA failed (e=%s)", errorCode);
                throw new SilentExitException();
            }
            // TODO: test this
            if(dataSize <= (data.length - dataPadding))
            {
                mode.echof("Error: RegQueryValueExA claimed %s bytes are needed to read the string but the buffer is already %s bytes (e=%s)",
                    dataSize, data.length, GetLastError());
                throw new SilentExitException();
            }
        }
    }

    auto trimNulls(T)(T slice)
    {
        for(; slice.length > 0 && slice[$-1] == '\0'; slice.length--)
        {
        }
        return slice;
    }

    string tryReadString(HKEY key, CString varname, bool ensureNullTerminated = false)
    {
        assert(!ensureNullTerminated, "ensureNullTerminated not implemented");
        auto data = tryReadData(key, varname, ensureNullTerminated ? 1 : 0);
        if(data.type == REG_SZ)
        {
            data.bytes = data.bytes.trimNulls();
        }
        else if(data.type == REG_EXPAND_SZ)
        {
            data.bytes = data.bytes.trimNulls();
        }
        else if(data.type == REG_MULTI_SZ)
        {
            assert(0, "not implemented");
        }
        else if(data.type == REG_NONE)
        {
            return null;
        }
        else
        {
            assert(0, "not implemented");
        }

        //mode.echof("readString \"%s\" is \"%s\"", name, cast(char[])data.bytes);

        return cast(string)data.bytes;
    }

    string tryReadString(HKEY parentkey, CString registryPath, CString varname, bool ensureNullTerminated = false)
    {
        HKEY environmentKey;
        {
            auto errorCode = RegOpenKeyExA(parentkey, registryPath.ptr,
                0, KEY_QUERY_VALUE, &environmentKey);
            if(errorCode != ERROR_SUCCESS)
            {
                // TODO: use FormatMessage to get a description
                mode.echof("Error: RegOpenKeyExA(\"%s\") failed (e=%s)", registryPath.slice, GetLastError());
                throw new SilentExitException();
            }
        }
        scope(exit) RegCloseKey(environmentKey);

        return tryReadString(environmentKey, varname, ensureNullTerminated);
    }

    immutable USER_ENV_REGISTRY_PATH = immutable CString("Environment\0");
    immutable SYSTEM_ENV_REGISTRY_PATH = immutable CString("SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment\0");

    auto tryRegistryGetUserEnv(CString varname)
    {
        return tryReadString(HKEY_CURRENT_USER, USER_ENV_REGISTRY_PATH, varname);
    }
    auto registryGetUserEnv(CString varname)
    {
        auto result = tryRegistryGetUserEnv(varname);
        if(result is null)
        {
            mode.echof("Error: registry is missing HKEY_CURRENT_USER\\%s\\%s", USER_ENV_REGISTRY_PATH.slice, varname.slice);
            throw new SilentExitException();
        }
        return result;
    }

    auto tryRegistryGetSystemEnv(CString varname)
    {
        return tryReadString(HKEY_LOCAL_MACHINE, SYSTEM_ENV_REGISTRY_PATH, varname);
    }
    auto registryGetSystemEnv(CString varname)
    {
        auto result = tryRegistryGetSystemEnv(varname);
        if(result is null)
        {
            mode.echof("Error: registry is missing HKEY_LOCAL_MACHINE\\%s\\%s", SYSTEM_ENV_REGISTRY_PATH.slice, varname.slice);
            throw new SilentExitException();
        }
        return result;
    }

    string registryGetUserOrSystemEnvWithString(const(char)[] varname)
    {
        auto varnameCString = varname.tempCString();
        return registryGetUserOrSystemEnv(CString(varnameCString.ptr[0..varname.length+1]));
    }
    string registryGetUserOrSystemEnv(CString varname)
    {
        auto result = tryRegistryGetUserEnv(varname);
        if(result is null)
        {
            result = tryRegistryGetSystemEnv(varname);
        }
        if(result is null)
        {
            mode.echof("Error: failed to resolve \"%s\" as a user or system environment variable from the registry", varname.slice);
        }
        return result;
    }

    @property auto expandFormat(const(char)[] str, string function(const(char)[]) getVar)
    {
        static struct Formatter
        {
            const(char)[] str;
            string function(const(char)[]) getVar;
            void toString(scope void delegate(const(char)[]) sink)
            {
                size_t start = 0;
                size_t next = 0;
              find_percents_loop:
                for(;; next++)
                {
                    if(next == str.length)
                    {
                        break;
                    }
                    if(str[next] == '%')
                    {
                        sink(str[start..next]);
                        start = next;
                        for(;;)
                        {
                            next++;
                            if(next == str.length)
                            {
                                break find_percents_loop;
                            }
                            if(str[next] == '%')
                            {
                                break;
                            }
                        }
                        auto varName = str[start+1..next];

                        //mode.echof("varName is (start=%s, next=%s)\"%s\"", start, next, varName);
                        //auto expanded = environment.get(varName, null);
                        auto expanded = getVar(varName);

                        if(expanded)
                        {
                            sink(expanded);
                        }
                        else
                        {
                            sink(str[start..next+1]);
                        }
                        start = next + 1;
                    }
                }
                assert(next == str.length);
                if(next > start)
                {
                    sink(str[start..$]);
                }
            }
        }
        return Formatter(str, getVar);
    }

    version(unittest)
    {
        string[string] sharedVarMap;
        string getSharedVarMap(const(char)[] key)
        {
            return sharedVarMap.get(cast(string)key, null);
        }
    }

    unittest
    {
        void test(string test, string expected)
        {
            //mode.echof("-----------------------------------");
            //mode.echof("test    \"%s\"", test);
            auto actual = format("%s", test.expandFormat(&getSharedVarMap));
            //if(expected != actual)
            //{
            //    mode.echof("original \"%s\"", test);
            //    mode.echof("expected \"%s\"", expected);
            //    mode.echof("actual   \"%s\"", actual);
            //}
            assert(actual == expected);
        }
        test("", "");
        test("a", "a");
        test("abcd", "abcd");

        {
            sharedVarMap = sharedVarMap.init;
            sharedVarMap["SOME_TEST_VAR"] =  "a test value";
            test("abc%SOME_TEST_VAR%def", "abca test valuedef");

            //test("abc%some_test_var%def", "abca test valuedef");
            //test("abc%sOme_tESt_vAr%def", "abca test valuedef");
            // TODO: test that on windows it is case-insenstive
        }

        test("abc%AN_OBVIOUSLY_MISSING_VARIABLE_NAME%def", "abc%AN_OBVIOUSLY_MISSING_VARIABLE_NAME%def");
        test("abc%def", "abc%def");

        test("%%", "%%");
        test("%%abcd", "%%abcd");
        test("ab%%cd", "ab%%cd");
        test("abcd%%", "abcd%%");
    }
}
