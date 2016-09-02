<#
    .Author
    http://superuser.com/questions/881547/how-to-determine-if-two-directory-pathnames-resolve-to-the-same-target
#>
function Global:LoadCode()
{
    Add-Type -MemberDefinition @"

    [StructLayout(LayoutKind.Sequential)]
    public struct BY_HANDLE_FILE_INFORMATION
    {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    };

    [DllImport("kernel32.dll", SetLastError = true)]
     private static extern bool GetFileInformationByHandle(IntPtr hFile, out BY_HANDLE_FILE_INFORMATION lpFileInformation);

    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
     public static extern SafeFileHandle CreateFile(string lpFileName, int dwDesiredAccess, int dwShareMode,
     IntPtr SecurityAttributes, int dwCreationDisposition, int dwFlagsAndAttributes, IntPtr hTemplateFile);

    private static SafeFileHandle MY_GetFileHandle(string dirName)
    {
        const int FILE_ACCESS_NEITHER = 0;
        const int FILE_SHARE_READ = 1;
        const int FILE_SHARE_WRITE = 2;
        const int CREATION_DISPOSITION_OPEN_EXISTING = 3;
        const int FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        return CreateFile(dirName, FILE_ACCESS_NEITHER, (FILE_SHARE_READ | FILE_SHARE_WRITE), System.IntPtr.Zero, CREATION_DISPOSITION_OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, System.IntPtr.Zero);
    }

    private static BY_HANDLE_FILE_INFORMATION? MY_GetFileInfo(SafeFileHandle directoryHandle)
    {
        BY_HANDLE_FILE_INFORMATION objectFileInfo;
        if ((directoryHandle == null) || (!GetFileInformationByHandle(directoryHandle.DangerousGetHandle(), out objectFileInfo)))
        {
            return null;
        }
        return objectFileInfo;
    }

    public static bool MY_AreDirsEqual(string dirName1, string dirName2)
    { //
        bool bRet = false;
        //NOTE: we cannot lift the call to GetFileHandle into GetFileInfo, because we _must_
        // have both file handles open simultaneously in order for the objectFileInfo comparison
        // to be guaranteed as valid.
        using (SafeFileHandle directoryHandle1 = MY_GetFileHandle(dirName1), directoryHandle2 = MY_GetFileHandle(dirName2))
        {
            BY_HANDLE_FILE_INFORMATION? objectFileInfo1 = MY_GetFileInfo(directoryHandle1);
            BY_HANDLE_FILE_INFORMATION? objectFileInfo2 = MY_GetFileInfo(directoryHandle2);
            bRet = objectFileInfo1 != null
                    && objectFileInfo2 != null
                    && (objectFileInfo1.Value.FileIndexHigh == objectFileInfo2.Value.FileIndexHigh)
                    && (objectFileInfo1.Value.FileIndexLow == objectFileInfo2.Value.FileIndexLow)
                    && (objectFileInfo1.Value.VolumeSerialNumber == objectFileInfo2.Value.VolumeSerialNumber);
        }
        return bRet;
    }
"@ -Name Win32 -NameSpace System -UsingNamespace System.Text,Microsoft.Win32.SafeHandles,System.ComponentModel
}

function Global:Get_AreDirsEqual([string]$p_source, [string]$p_target)
{   
    if( ( ([System.Management.Automation.PSTypeName]'System.Win32').Type -eq $null)  -or ([system.win32].getmethod('MY_AreDirsEqual') -eq $null) )
    {
        LoadCode
    }
    [System.Win32]::MY_AreDirsEqual($p_source, $p_target)
}
