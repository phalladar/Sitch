using System.Runtime.InteropServices;
using System.Windows.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;
using Windows.Foundation;
using Windows.Storage;
using Windows.Storage.Streams;
using WinSitch.Shell;

namespace WinSitch.Export;

/// <summary>
/// Native Windows Share sheet from an unpackaged exe via IDataTransferManagerInterop.
/// Hardened per Chromium's approach: handler can never throw (the OS may kill the process),
/// the manager stays rooted while its window lives, and failures degrade to clipboard copy.
/// </summary>
public static class ShareHelper
{
    [ComImport, Guid("3A3DCD6C-3EAB-43DC-BCDE-45671CE800C8"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDataTransferManagerInterop
    {
        IntPtr GetForWindow([In] IntPtr appWindow, [In] ref Guid riid);
        void ShowShareUIForWindow(IntPtr appWindow);
    }

    private static readonly Guid DtmIid = new("a5caee9b-8708-49d1-8d36-67d25a8da00c");

    // Keep managers + handlers rooted per window (GC'd handlers = silent share no-shows).
    private static readonly Dictionary<IntPtr, (DataTransferManager Dtm, TypedEventHandler<DataTransferManager, DataRequestedEventArgs> Handler)> Registered = new();

    /// <summary>
    /// Shows the share sheet for the flattened image. Most share targets only accept image
    /// FILES, so we share a temp PNG StorageFile plus a bitmap stream (never bitmap-only).
    /// </summary>
    public static async void TryShare(IntPtr hwnd, BitmapSource bitmap, string title,
        Func<BitmapSource, string> writeTempPng)
    {
        try
        {
            string path = writeTempPng(bitmap);
            // Resolve the StorageFile off the UI thread; the DataRequested handler then stays sync
            // and comfortably inside the OS's 200 ms budget.
            var file = await Task.Run(() => StorageFile.GetFileFromPathAsync(path).AsTask()).ConfigureAwait(true);

            var interop = DataTransferManager.As<IDataTransferManagerInterop>();
            var iid = DtmIid;

            if (Registered.TryGetValue(hwnd, out var old))
            {
                old.Dtm.DataRequested -= old.Handler;
                Registered.Remove(hwnd);
            }

            // GetForWindow returns a caller-owned reference; FromAbi AddRefs, so release ours.
            IntPtr abi = interop.GetForWindow(hwnd, ref iid);
            DataTransferManager dtm;
            try { dtm = WinRT.MarshalInterface<DataTransferManager>.FromAbi(abi); }
            finally { Marshal.Release(abi); }

            TypedEventHandler<DataTransferManager, DataRequestedEventArgs> handler = (_, args) =>
            {
                try
                {
                    var data = args.Request.Data;
                    data.Properties.Title = title;
                    data.Properties.Description = "Annotated with WinSitch";
                    data.SetStorageItems([file]);
                    data.SetBitmap(RandomAccessStreamReference.CreateFromFile(file));
                }
                catch
                {
                    // Never let an exception escape: the OS can kill the process for a FAILED return.
                }
            };
            dtm.DataRequested += handler;
            Registered[hwnd] = (dtm, handler);

            interop.ShowShareUIForWindow(hwnd);
        }
        catch
        {
            // Share sheet unavailable (OS state, elevated process, …) — degrade gracefully.
            if (ClipboardHelper.CopyImage(bitmap))
                NotifyPopup.Show("Share isn't available here — copied to clipboard instead.");
            else
                NotifyPopup.Show("Share isn't available right now.");
        }
    }

    /// <summary>Call when a window closes so its DTM/handler/StorageFile don't stay rooted forever.</summary>
    public static void Detach(IntPtr hwnd)
    {
        if (Registered.Remove(hwnd, out var entry))
        {
            try { entry.Dtm.DataRequested -= entry.Handler; } catch { }
        }
    }
}
