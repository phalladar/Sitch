using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;

namespace Sitch.Shell;

/// <summary>Named-mutex single instance with a named-pipe channel for arg hand-off.</summary>
public sealed class SingleInstance : IDisposable
{
    private static string MutexName => $"Sitch-{Environment.UserName}-4E1C7A";
    private static string PipeName => $"Sitch-pipe-{Environment.UserName}";

    [DllImport("user32.dll")]
    private static extern bool AllowSetForegroundWindow(int dwProcessId);
    private const int AsfwAny = -1;

    private readonly Mutex _mutex;
    private readonly CancellationTokenSource _cts = new();

    private SingleInstance(Mutex mutex, Action<string> onMessage)
    {
        _mutex = mutex;
        _ = RunServerAsync(onMessage, _cts.Token);
    }

    /// <summary>Returns null when another instance already owns the mutex.</summary>
    public static SingleInstance? TryAcquire(Action<string> onMessage)
    {
        var mutex = new Mutex(initiallyOwned: true, MutexName, out bool createdNew);
        if (createdNew) return new SingleInstance(mutex, onMessage);
        mutex.Dispose();
        return null;
    }

    public static void SendToPrimary(string[] args)
    {
        try
        {
            // Let the primary instance bring its window to the foreground.
            AllowSetForegroundWindow(AsfwAny);
            using var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out,
                PipeOptions.CurrentUserOnly);
            client.Connect(1500);
            using var writer = new StreamWriter(client, Encoding.UTF8);
            bool sent = false;
            foreach (var a in args)
            {
                if (a == "--capture") { writer.WriteLine("CAPTURE"); sent = true; }
                else if (a == "--settings") { writer.WriteLine("SETTINGS"); sent = true; }
                else if (File.Exists(a)) { writer.WriteLine("OPEN " + Path.GetFullPath(a)); sent = true; }
            }
            if (!sent) writer.WriteLine("FOCUS");
            writer.Flush();
        }
        catch { /* primary unreachable — nothing to do */ }
    }

    private async Task RunServerAsync(Action<string> onMessage, CancellationToken ct)
    {
        await Task.Yield(); // never run pipe work synchronously inside the ctor / UI thread
        while (!ct.IsCancellationRequested)
        {
            try
            {
                await using var server = new NamedPipeServerStream(
                    PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await server.WaitForConnectionAsync(ct);

                // Per-connection deadline so one wedged client can't park the listener forever.
                using var connCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                connCts.CancelAfter(TimeSpan.FromSeconds(5));
                using var reader = new StreamReader(server, Encoding.UTF8);
                try
                {
                    while (await reader.ReadLineAsync(connCts.Token) is { } line)
                        if (line.Length > 0) onMessage(line);
                }
                catch (OperationCanceledException) when (!ct.IsCancellationRequested)
                {
                    // wedged client — drop the connection, keep serving
                }
            }
            catch (OperationCanceledException) { break; }
            catch
            {
                // Pipe name busy (old instance still dying, or a squatter) — back off, don't spin.
                try { await Task.Delay(250, ct); } catch (OperationCanceledException) { break; }
            }
        }
    }

    public void Dispose()
    {
        _cts.Cancel();
        try { _mutex.ReleaseMutex(); } catch { }
        _mutex.Dispose();
    }
}
