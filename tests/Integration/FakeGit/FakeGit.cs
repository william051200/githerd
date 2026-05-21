using System;
using System.IO;
using System.Threading;

// ============================================================
// Fake git for sync.bat integration tests.
//
//   Compiled at test-time into FakeGit/git.exe by SyncBat.Tests.ps1.
//   Built as a .exe (not .cmd) so that sync.bat's worker - which
//   invokes `git ...` without `call` - actually returns control
//   to the worker after the fake exits. (A .cmd invoked from a
//   .bat without `call` terminates the caller.)
//
// Environment variables:
//   FAKEGIT_LOG            File to append "cwd|args" per call.
//   FAKEGIT_DIRTY          If set, "git status --porcelain"
//                          prints one modified file.
//   FAKEGIT_BRANCH         Value returned by "git branch
//                          --show-current". Default: main.
//   FAKEGIT_SLEEP_SECONDS  Sleep N seconds before exiting.
//   FAKEGIT_FAIL_FIRST     First arg that should fail
//                          (case-insensitive).
//   FAKEGIT_FAIL_SECOND    If set, also require the second arg
//                          to match to fail.
//   FAKEGIT_LOCAL_SHA      SHA returned by "git rev-parse <branch>".
//                          If unset, rev-parse prints nothing.
//   FAKEGIT_ORIGIN_SHA     SHA used in "git ls-remote origin <branch>"
//                          output. If unset, ls-remote prints nothing.
//   FAKEGIT_UPSTREAM_SHA   SHA used in "git ls-remote upstream <branch>"
//                          output. If unset, ls-remote prints nothing.
// ============================================================

internal static class FakeGit
{
    private static int Main(string[] args)
    {
        var log = Environment.GetEnvironmentVariable("FAKEGIT_LOG");
        if (!string.IsNullOrEmpty(log))
        {
            try
            {
                File.AppendAllText(
                    log,
                    Environment.CurrentDirectory + "|" + string.Join(" ", args) + Environment.NewLine);
            }
            catch
            {
                // best-effort; do not fail the test on a write race
            }
        }

        var sleepStr = Environment.GetEnvironmentVariable("FAKEGIT_SLEEP_SECONDS");
        int sleep;
        if (!string.IsNullOrEmpty(sleepStr) && int.TryParse(sleepStr, out sleep) && sleep > 0)
        {
            Thread.Sleep(sleep * 1000);
        }

        string first = args.Length > 0 ? args[0] : string.Empty;
        string second = args.Length > 1 ? args[1] : string.Empty;

        if (string.Equals(first, "status", StringComparison.OrdinalIgnoreCase))
        {
            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("FAKEGIT_DIRTY")))
            {
                Console.WriteLine(" M file.txt");
            }
            return 0;
        }

        if (string.Equals(first, "branch", StringComparison.OrdinalIgnoreCase))
        {
            var branch = Environment.GetEnvironmentVariable("FAKEGIT_BRANCH");
            if (string.IsNullOrEmpty(branch))
            {
                branch = "main";
            }
            Console.WriteLine(branch);
            return 0;
        }

        if (string.Equals(first, "rev-parse", StringComparison.OrdinalIgnoreCase))
        {
            var localSha = Environment.GetEnvironmentVariable("FAKEGIT_LOCAL_SHA");
            if (!string.IsNullOrEmpty(localSha))
            {
                Console.WriteLine(localSha);
            }
            return 0;
        }

        if (string.Equals(first, "ls-remote", StringComparison.OrdinalIgnoreCase))
        {
            // args: ls-remote <remote> <branch>
            string remote = args.Length > 1 ? args[1] : string.Empty;
            string branch = args.Length > 2 ? args[2] : "main";
            string envName = "FAKEGIT_" + remote.ToUpperInvariant() + "_SHA";
            var sha = Environment.GetEnvironmentVariable(envName);
            if (!string.IsNullOrEmpty(sha))
            {
                Console.WriteLine(sha + "\trefs/heads/" + branch);
            }
            return 0;
        }

        var failFirst = Environment.GetEnvironmentVariable("FAKEGIT_FAIL_FIRST");
        if (!string.IsNullOrEmpty(failFirst) &&
            string.Equals(first, failFirst, StringComparison.OrdinalIgnoreCase))
        {
            var failSecond = Environment.GetEnvironmentVariable("FAKEGIT_FAIL_SECOND");
            if (string.IsNullOrEmpty(failSecond) ||
                string.Equals(second, failSecond, StringComparison.OrdinalIgnoreCase))
            {
                return 1;
            }
        }

        return 0;
    }
}
