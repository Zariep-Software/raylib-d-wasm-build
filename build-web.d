#!/usr/bin/env rdmd

module build_web;

import std.algorithm;
import std.array;
import std.ascii : isAlpha, isAlphaNum;
import std.conv;
import std.exception;
import std.file;
import std.path;
import std.process;
import std.stdio;
import std.string;

version (Windows)
{
	enum emrunName = "emrun.bat";
}
else
{
	enum emrunName = "emrun";
}

// Env helpers (same as build_android.d) //

string requireEnv(string name, string hint = null)
{
	auto v = environment.get(name);
	enforce(v !is null && v.length > 0,
		"Set " ~ name ~ (hint.length ? " (" ~ hint ~ ")" : ""));
	return v;
}

string envOr(string name, string dflt)
{
	auto v = environment.get(name);
	return (v is null || v.length == 0) ? dflt : v;
}

string expandEnvVars(string value)
{
	if (value.length == 0)
		return value;

	if (value == "~" || value.startsWith("~/"))
	{
		auto home = environment.get("HOME", "");
		value = home ~ value[1 .. $];
	}

	auto result = appender!string;
	size_t i = 0;
	while (i < value.length)
	{
		if (value[i] == '$' && i + 1 < value.length)
		{
			if (value[i + 1] == '{')
			{
				auto close = value.indexOf('}', i + 2);
				if (close >= 0)
				{
					result.put(environment.get(value[i + 2 .. close], ""));
					i = close + 1;
					continue;
				}
			}
			else if (isAlpha(value[i + 1]) || value[i + 1] == '_')
			{
				size_t j = i + 1;
				while (j < value.length && (isAlphaNum(value[j]) || value[j] == '_'))
					j++;
				auto resolved = environment.get(value[i + 1 .. j], null);
				result.put(resolved is null ? value[i .. j] : resolved);
				i = j;
				continue;
			}
		}
		result.put(value[i]);
		i++;
	}
	return result.data;
}

void loadEnvFile(string path)
{
	if (!exists(path))
		return;

	foreach (rawLine; File(path).byLine)
	{
		auto line = rawLine.idup.strip;
		if (line.length == 0 || line.startsWith("#"))
			continue;
		if (line.startsWith("export "))
			line = line["export ".length .. $].strip;

		auto eq = line.indexOf('=');
		if (eq < 0)
			continue;

		auto key = line[0 .. eq].strip;
		auto val = line[eq + 1 .. $].strip;

		if (val.length >= 2 &&
			((val[0] == '"' && val[$ - 1] == '"') ||
			(val[0] == '\'' && val[$ - 1] == '\'')))
		{
			val = val[1 .. $ - 1];
		}

		environment[key] = expandEnvVars(val);
	}
}

// Subprocess helpers //

void run(string[] cmd, string[string] extraEnv = null)
{
	auto fullEnv = environment.toAA;
	foreach (k, v; extraEnv)
		fullEnv[k] = v;

	writeln("== ", cmd.join(" "));
	auto pid = spawnProcess(cmd, fullEnv);
	auto status = wait(pid);
	enforce(status == 0, cmd[0] ~ " failed with exit code " ~ status.to!string);
}

struct HookResult
{
	string extraCFlags;
	string extraLdFlags;
	string extraDFlags;
}

HookResult runHook(string scriptName, string[] args, string[string] extraEnv = null)
{
	HookResult result;

	if (!exists(scriptName) || !isFile(scriptName))
		return result;

	version (Posix)
	{
		import core.sys.posix.sys.stat : S_IXUSR, S_IXGRP, S_IXOTH;
		auto mode = getAttributes(scriptName);
		if ((mode & (S_IXUSR | S_IXGRP | S_IXOTH)) == 0)
		{
			writeln("== Skipping ", scriptName, " (found but not executable; run: chmod +x ", scriptName, ")");
			return result;
		}
	}

	auto fullEnv = environment.toAA;
	foreach (k, v; extraEnv)
		fullEnv[k] = v;

	writeln("== Running ", scriptName, " ", args.join(" "));

	auto scriptPath = isAbsolute(scriptName) ? scriptName : "./" ~ scriptName;
	auto pipes = pipeProcess([scriptPath] ~ args, Redirect.stdout, fullEnv);

	string[] cParts, lParts, dParts;
	foreach (rawLine; pipes.stdout.byLine)
	{
		auto line = rawLine.idup.strip;
		if (line.length == 0)
			continue;

		writeln("   [", scriptName, "] ", line);

		if (line.startsWith("EXTRA_CFLAGS="))
			cParts ~= line["EXTRA_CFLAGS=".length .. $].strip;
		else if (line.startsWith("EXTRA_LDFLAGS="))
			lParts ~= line["EXTRA_LDFLAGS=".length .. $].strip;
		else if (line.startsWith("EXTRA_DFLAGS="))
			dParts ~= line["EXTRA_DFLAGS=".length .. $].strip;
	}

	auto status = wait(pipes.pid);
	enforce(status == 0, scriptName ~ " failed with exit code " ~ status.to!string);

	result.extraCFlags = cParts.filter!(s => s.length > 0).join(" ");
	result.extraLdFlags = lParts.filter!(s => s.length > 0).join(" ");
	result.extraDFlags = dParts.filter!(s => s.length > 0).join(" ");
	return result;
}

string appendFlag(string existing, string extra)
{
	if (extra.length == 0)
		return existing;
	return existing.length == 0 ? extra : existing ~ " " ~ extra;
}

// raylib-d import path discovery via `dub describe` //

string getImportPathFromDub(string packageName, string packageSourceName = "source")
{
	auto target = buildPath(packageName, packageSourceName);
	version (Windows)
		target ~= `\"`;
	else
		target ~= `/"`;

	auto content = execute(["dub", "describe"]).output;
	size_t lineIndex = 0;
	foreach (i, c; content)
	{
		if (c != '\n')
			continue;
		auto line = content[lineIndex .. i].strip().strip(",");
		if (line.endsWith(target))
			return line[line.indexOf('"') + 1 .. $ - 1];
		lineIndex = i + 1;
	}
	return "";
}

// HTML shell //

enum defaultShell = `<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <meta name="viewport" content="width=device-width">
    <title>App</title>
    <style>
/* WEB_CSS */
    </style>
</head>
<body>
    <div id="loading"><div class="spinner"></div></div>
    <canvas class="emscripten" id="canvas" oncontextmenu="event.preventDefault()" tabindex="-1"></canvas>
    <script>
        var Module = {
            canvas: document.getElementById('canvas'),
            postRun: [function() {
                document.getElementById("loading").style.display = "none";
                document.getElementById("canvas").style.display = "block";
            }]
        };
    </script>
    {{{ SCRIPT }}}
</body>
</html>
`;

enum defaultCss = `body { margin: 0; overflow: hidden; background: #000; }
canvas.emscripten { border: 0; background: #000; display: none; }
#loading { position: fixed; inset: 0; display: flex; justify-content: center; align-items: center; background: rgba(0,0,0,.5); }
.spinner { width: 120px; height: 120px; border: 16px solid #c0c0c0; border-top-color: #343434; border-radius: 50%; animation: spin 2s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
`;

// Builds the final shell file (custom or default HTML, with CSS merged in) in a temp dir.
string prepareShell()
{
	auto shellPath = expandEnvVars(envOr("WEB_SHELL_PATH", ""));
	auto cssPath = expandEnvVars(envOr("WEB_CSS_PATH", ""));

	string html;
	if (shellPath.length)
	{
		enforce(exists(shellPath), "WEB_SHELL_PATH not found: " ~ shellPath);
		html = readText(shellPath);
	}
	else
	{
		html = defaultShell;
	}

	string css;
	if (cssPath.length)
	{
		enforce(exists(cssPath), "WEB_CSS_PATH not found: " ~ cssPath);
		css = readText(cssPath);
	}
	else if (shellPath.length == 0)
	{
		css = defaultCss;
	}

	enum marker = "/* WEB_CSS */";
	if (css.length)
	{
		if (html.canFind(marker))
			html = html.replace(marker, css);
		else if (html.canFind("</head>"))
			html = html.replace("</head>", "<style>\n" ~ css ~ "\n</style>\n</head>");
		else
			html = "<style>\n" ~ css ~ "\n</style>\n" ~ html;
	}

	enforce(html.canFind("{{{ SCRIPT }}}"),
		"HTML shell must contain the emscripten placeholder {{{ SCRIPT }}}");

	auto dir = buildPath(tempDir(), "ldc2-web-shell");
	mkdirRecurse(dir);
	auto outPath = buildPath(dir, "shell.html");
	std.file.write(outPath, html);
	return outPath;
}

void traceFile(string label, string path)
{
	if (!exists(path))
	{
		writefln("   %-8s %s  (MISSING)", label, path);
		return;
	}
	auto e = DirEntry(path);
	writefln("   %-8s %s  %s bytes, modified %s", label, path, e.size, e.timeLastModified);
}

void traceTree(string label, string dir)
{
	if (!exists(dir) || !isDir(dir))
	{
		writefln("   %-8s %s  (MISSING DIR)", label, dir);
		return;
	}
	foreach (e; dirEntries(dir, SpanMode.depth))
		if (e.isFile)
			traceFile(label, e.name);
}

struct Flags
{
	bool betterc;
	bool release;
	bool build;
	bool trace;
}

enum helpText = "Usage:
  rdmd build_web.d [flags]
Flags:
  -betterc  Use the `-betterC` flag.
  -release  Use `-release -O2` instead of debug.
  -build    Avoid emrun after a successful build.";

int main(string[] args)
{
	loadEnvFile("./websetup.sh");

	Flags flags;
	foreach (arg; args[1 .. $])
	{
		auto a = arg.chompPrefix("--").chompPrefix("-");
		switch (a)
		{
			case "betterc": flags.betterc = true; break;
			case "release": flags.release = true; break;
			case "build": flags.build = true; break;
			case "trace": flags.trace = true; break;
			default:
				writeln(helpText);
				return 0;
		}
	}

	// Optional emsdk on PATH (emcc is used by ldc2 as the linker driver)
	string[string] buildEnv;
	auto emsdk = expandEnvVars(envOr("EMSDK_DIR", ""));
	if (emsdk.length)
	{
		auto emDir = buildPath(emsdk, "upstream", "emscripten");
		enforce(isDir(emDir), "EMSDK_DIR has no upstream/emscripten: " ~ emDir);
		buildEnv["PATH"] = emDir ~ pathSeparator ~ environment.get("PATH", "");
		environment["PATH"] = buildEnv["PATH"];
	}
	auto emccPath = envOr("EMCC", "emcc");
	environment["CC"] = emccPath;

	// Paths
	auto sourcePath = envOr("WEB_SOURCE_DIR", "");
	if (sourcePath.length == 0)
	{
		sourcePath = "source";
		if (!sourcePath.exists) sourcePath = "src";
		if (!sourcePath.exists) sourcePath = ".";
	}
	enforce(isDir(sourcePath), "Source dir not found: " ~ sourcePath);

	auto assetsPath = envOr("WEB_ASSETS_DIR", "assets");
	auto webPath = envOr("WEB_OUTPUT_DIR", "web");
	mkdirRecurse(webPath);

	auto raylibImportPath = envOr("RAYLIB_D_IMPORT", "");
	if (raylibImportPath.length == 0)
		raylibImportPath = buildPath(sourcePath, "raylib").exists ? sourcePath : getImportPathFromDub("raylib-d");
	enforce(raylibImportPath.length, "Could not find raylib-d import path. Set RAYLIB_D_IMPORT.");

	auto raylibLibDir = expandEnvVars(requireEnv("RAYLIB_WEB_LIB_DIR",
		"dir containing libraylib.web.a or libraylib.a from the raylib webassembly release"));
	auto libPath = buildPath(raylibLibDir, "libraylib.web.a");
	if (!libPath.exists) libPath = buildPath(raylibLibDir, "libraylib.a");
	enforce(libPath.exists,
		"Missing libraylib(.web).a in " ~ raylibLibDir ~
		"\nDownload the webassembly zip from https://github.com/raysan5/raylib/releases");

	auto outputPath = buildPath(webPath, "index.html");
	auto shellPath = prepareShell();

	auto extraCFlags = envOr("EXTRA_CFLAGS", "");
	auto extraLdFlags = envOr("EXTRA_LDFLAGS", "");
	auto extraDFlags = envOr("EXTRA_DFLAGS", "");

	// Pre-build hook: webprebuild.sh <outputDir> <libPath> <sourceDir> <assetsDir>
	auto preHook = runHook("webprebuild.sh",
		[webPath, libPath, sourcePath, assetsPath],
		[
			"WEB_OUTPUT_DIR": webPath,
			"WEB_LIB_PATH": libPath,
			"WEB_SOURCE_DIR": sourcePath,
			"WEB_ASSETS_DIR": assetsPath,
			"WEB_SHELL_FILE": shellPath,
			"BUILD_MODE": flags.release ? "release" : "debug",
		]);
	extraCFlags = appendFlag(extraCFlags, preHook.extraCFlags);
	extraLdFlags = appendFlag(extraLdFlags, preHook.extraLdFlags);
	extraDFlags = appendFlag(extraDFlags, preHook.extraDFlags);

	auto mainFilePaths = dirEntries(sourcePath, SpanMode.shallow)
		.filter!(e => e.name.endsWith(".d"))
		.map!(e => e.name)
		.array;
	enforce(mainFilePaths.length, "No .d files in " ~ sourcePath);

	string[] dflags = ["-i", "-betterC", "--checkaction=halt"];
	dflags ~= flags.release ? ["-release", "-O2"] : ["--d-debug", "-g"];

	auto command = ["ldc2", "--mtriple=wasm32-emscripten", "-gcc=" ~ emccPath] ~ dflags;
	command ~= mainFilePaths;
	command ~= libPath;
	if (sourcePath != raylibImportPath)
		command ~= "-I=" ~ sourcePath;
	command ~= "-I=" ~ raylibImportPath;
	command ~= "-of=" ~ outputPath;
	command ~= "--Xcc=" ~ (flags.release ? "-O2" : "-g");
	command ~= "--Xcc=-DPLATFORM_WEB";
	command ~= "--Xcc=-sUSE_GLFW=3";
	command ~= "--Xcc=-sEXPORTED_RUNTIME_METHODS=HEAPF32,requestFullscreen";
	command ~= "--Xcc=-sINITIAL_MEMORY=" ~ envOr("INITIAL_MEMORY", "67108864");
	command ~= "--Xcc=-sALLOW_MEMORY_GROWTH=1";
	command ~= "--Xcc=--shell-file";
	command ~= "--Xcc=" ~ shellPath;

	// emcc complains about empty preload dirs, so only add it when there is something in it.
	if (assetsPath.exists && isDir(assetsPath) && !dirEntries(assetsPath, SpanMode.shallow).empty)
	{
		command ~= "--Xcc=--preload-file";
		command ~= "--Xcc=" ~ assetsPath;
	}

	foreach (tok; extraCFlags.split) command ~= "--Xcc=" ~ tok;
	foreach (tok; extraLdFlags.split) command ~= "--Xcc=" ~ tok;
	command ~= extraDFlags.split;


		if (flags.trace)
	{
		command ~= "-v"; // ldc2 lists every module it parses/imports (-i pulls in raylib-d files)
		command ~= "--Xcc=-sASSERTIONS=2";
		command ~= "--Xcc=-sSAFE_HEAP=1";          // traps on null/misaligned memory access
		command ~= "--Xcc=-sSTACK_OVERFLOW_CHECK=2";
		command ~= "--Xcc=-sFORCE_FILESYSTEM=1";
		command ~= "--Xcc=--emrun";                // emrun forwards console/printf to this terminal

		writeln("== Inputs ==");
		foreach (f; mainFilePaths) traceFile("source", f);
		traceFile("raylib", libPath);
		traceFile("shell", shellPath);
		traceTree("preload", assetsPath);
		writeln("== Resolved emcc/ldc2 command ==");
		writeln(command.join(" \\\n   "));
	}

	writeln("== Building D sources for wasm32-emscripten (", flags.release ? "release" : "debug", ") ==");
	writeln(" raylib: ", libPath);
	writeln(" shell:  ", shellPath);
	run(command);

	// Clean up stray object files left by ldc2
	foreach (dir; [".", webPath])
	{
		foreach (entry; dirEntries(dir, SpanMode.shallow))
		{
			if (entry.name.endsWith(".o") || entry.name.endsWith(".obj"))
				entry.remove();
		}
	}

	enforce(outputPath.exists, "Build finished but output missing: " ~ outputPath);

	// Post-build hook: webpostbuild.sh <outputHtml>
	runHook("webpostbuild.sh", [outputPath],
		["WEB_OUTPUT_DIR": webPath, "BUILD_MODE": flags.release ? "release" : "debug"]);

	writefln("DONE: \"\033[32m%s\033[0m\"", outputPath);

	if (flags.build)
		return 0;
	run([emrunName, outputPath]);
	return 0;
}