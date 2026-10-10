# dotnet watch crashes after a failed re-evaluation

`dotnet watch` crashes with a `NullReferenceException` and exit code 134 when a project
re-evaluation fails and then any watched file changes.

Seen with SDK 10.0.401 on macOS (arm64).

## Reproduce

```bash
./repro.sh
```

The script:

1. Starts `dotnet watch run` on a console app.
2. Creates the file `break-evaluation`. Adding a file makes `dotnet watch` re-evaluate the project.
   While that file exists, a target in `Repro.csproj` fails the design-time build. `dotnet watch`
   prints `Fix the error to continue or press Ctrl+C to exit.`
3. Deletes `break-evaluation`.

The target only stands in for any failure of that build. In the project where this was found, the
build failed because a script was replacing the files in `wwwroot` while `dotnet watch` re-evaluated.

## Expected

`dotnet watch` notices the change, re-evaluates, and continues.

## Actual

`dotnet watch` exits with code 134:

```
dotnet watch ⌚ Fix the error to continue or press Ctrl+C to exit.
Unhandled exception. System.NullReferenceException: Object reference not set to an instance of an object.
   at Microsoft.DotNet.Watch.HotReloadDotNetWatcher.AcceptChange(ChangedPath change, EvaluationResult evaluationResult)
   at Microsoft.DotNet.Watch.HotReloadDotNetWatcher.<>c__DisplayClass13_3.<WatchAsync>g__FileChangedCallback|1(ChangedPath change)
   at Microsoft.DotNet.Watch.FileWatcher.WatcherChangedHandler(Object sender, ChangedPath change)
   at Microsoft.DotNet.Watch.DirectoryWatcher.NotifyChange(String fullPath, ChangeKind kind)
   at Microsoft.DotNet.Watch.EventBasedDirectoryWatcher.WatcherDeletedHandler(Object sender, FileSystemEventArgs e)
   at System.IO.FileSystemWatcher.NotifyFileSystemEventArgs(WatcherChangeTypes changeType, ReadOnlySpan`1 name)
   ...
```

The app that `dotnet watch` started keeps running after `dotnet watch` has exited.

Depending on how macOS reports the event, the stack shows `WatcherAddedHandler` instead of
`WatcherDeletedHandler`. Any file event in the watched directory causes the crash.

## Cause (from reading the source at v10.0.401)

In `HotReloadDotNetWatcher.WatchAsync`:

- [`FileChangedCallback`](https://github.com/dotnet/sdk/blob/v10.0.401/src/Dotnet.Watch/Watch/HotReload/HotReloadDotNetWatcher.cs#L216)
  captures the local `evaluationResult` and is subscribed to `fileWatcher.OnFileChange`
  ([line 226](https://github.com/dotnet/sdk/blob/v10.0.401/src/Dotnet.Watch/Watch/HotReload/HotReloadDotNetWatcher.cs#L226)).
- When a change requires re-evaluation,
  [line 393](https://github.com/dotnet/sdk/blob/v10.0.401/src/Dotnet.Watch/Watch/HotReload/HotReloadDotNetWatcher.cs#L393)
  assigns the result of `TryEvaluateProjectGraphAsync` to that same local. If evaluation fails,
  that result is `null`. The callback stays subscribed while the loop waits for the next change.
- On the next file event, the callback passes `null` to
  [`AcceptChange`](https://github.com/dotnet/sdk/blob/v10.0.401/src/Dotnet.Watch/Watch/HotReload/HotReloadDotNetWatcher.cs#L790),
  which reads `evaluationResult.Files`. The exception is thrown on a `FileSystemWatcher` thread
  pool callback, so it is unhandled and the process aborts.

The code is unchanged on `main` as of 2026-10-10.
