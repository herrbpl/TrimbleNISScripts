<# 
	.Synopsis
		Makes sure that WMS storage is set to local disk and starts Trimble NIS
	.Description
		Makes sure that WMS storage is set to local disk and starts Trimble NIS
	.Parameter TrimbleConfigPath
		Path to Trimble NIS config 
    .Parameter TrimbleExecutablePath
		Path to Trimble NIS executable
    .Parameter WMSSourcePath
		Path to WMS source  path. Defaults to \\ntserver2.sise\ASTV\NIS-PR\wms
    .Parameter WMSTargetPath
		Path to WMS target path. Defaults to C:\Tekla\WMS
    .Parameter UpdateWMSConfig
		If to update map files
    .Parameter ForceUpdateWMSConfig
		Force update of map files. Needs -UpdateWMSConfig
    .Parameter RunTrimbleNIS
		Runs Trimble NIS
    .Parameter TrimbleArguments
		Arguments for Trimble NIS Execution
    .Parameter verbose
		Verbose output
	
#>

Param(
  [string]$TrimbleConfigPath = "\\ntserver2.sise\ASTV\NIS-PR\config\NisLocalSettings-SiimTest.cfg",
  [string]$TrimbleExecutablePath = "\\NIS\TeklaProgram\Xpipe\bin\Xpipe.exe",
  [string]$WMSSourcePath = "\\ntserver2.sise\ASTV\NIS-PR\wms", 
  [string]$WMSTargetPath = "C:\Tekla\WMS",
  [switch]$UpdateWMSConfig = $False,
  [switch]$ForceUpdateWMSConfig = $False,
  [switch]$RunTrimbleNIS = $False,
  [string]$TrimbleArguments = "",
  [switch]$verbose
)


$oldverbose = $VerbosePreference
if($verbose) { $VerbosePreference = "continue" }


if (!(Test-Path $TrimbleConfigPath)) {
    $VerbosePreference = $oldverbose
    throw ("Cannot find path '{1}'" -f $TrimbleConfigPath) 
    exit 1
}


if ($RunTrimbleNIS) {
    if (!(Test-Path $TrimbleExecutablePath)) {
        $VerbosePreference = $oldverbose
        throw ("Cannot find path '{1}'" -f $TrimbleExecutablePath)
        exit 1
    }
}

if ($UpdateWMSConfig) {
    
    if (!(Test-Path $WMSSourcePath)) {
        $VerbosePreference = $oldverbose
        throw ("Cannot find path '{1}'" -f $WMSSourcePath)
        exit 1
    }

    if ($WMSTargetPath -eq $null -or $WMSTargetPath -eq "") {
        $temp = ((Get-Content $TrimbleConfigPath) -match "^WMSMAPDIRECTORY(.)*$")[0].Trim()
        if ($temp.IndexOf('=') -ge 0) {
            $WMSTargetPath = $temp.Split('=')[1].Trim()
        }

    }
    
    if ($WMSTargetPath -eq $null -or $WMSTargetPath -eq "") {
        $VerbosePreference = $oldverbose
        throw ("Cannot find WMSTargetPath '{1}'" -f $WMSTargetPath)
        exit 1
    }
}



Function Test-IfCopyFile {
    Param(        
      [Parameter(Mandatory=$True)][string]$sourcefile,
      [Parameter(Mandatory=$True)][string]$targetfile,
      [switch]$ForceUpdate = $False
    )

    if (!(test-path $sourcefile)) { 
        return $false
    }

    if (!(test-path $targetfile)) { 
        return $true
    }

    if ($ForceUpdate -or ((ls $targetfile).LastWriteTime -gt (ls $sourcefile).LastWriteTime )) {
        return $true
    }

    return $false
}


Function UpdateWMSConfig {
    Param(
        
      [Parameter(Mandatory=$True)][string]$sourceDir,
      [Parameter(Mandatory=$True)][string]$targetDir,
      [switch]$ForceUpdateWMSConfig = $False
    )

    $tempFileName = [System.IO.Path]::GetRandomFileName()
    
    if ( ($tempFileName -eq $null) -or ($tempFileName -eq "") -or ($tempFileName.indexOf('*') -ge 0) ) {
        $VerbosePreference = $oldverbose
        throw ("Failing to create temp file name")
        exit 1
    }

    $tempFileContent = $tempFileName

    $d1 = $sourceDir+"\"+$tempFileName
    $d2 = $targetDir+"\"+$tempFileName

    if (Test-Path $d1) {
        $VerbosePreference = $oldverbose
        throw ("Test tempfile {0} already exist in '{1}'" -f $tempFileName, $sourceDir)
        exit 1
    }

    $tempFileContent  | Out-File -FilePath $d1


    if (Test-Path $d2) {
        Remove-Item -Path $d1 | Out-Null
        $VerbosePreference = $oldverbose
        throw ("It appears that {0} and {1} point to same directory. Cannot continue'" -f $sourceDir, $targetDir)
        exit 1
    }

    Remove-Item -Path $d1 | Out-Null


    #return


    if ($sourceDir -eq $targetDir) {
        throw "Target and source cannot be same directory"
    }


    # Create target directory

    if (!(Test-Path $targetDir)) {
        new-item -ItemType Directory -Force -Path $targetDir | Out-Null

        $Acl = Get-Acl $targetDir
        $Ar = New-Object  system.security.accesscontrol.filesystemaccessrule("Domain Users","FullControl",  'ContainerInherit,ObjectInherit', 'None', "Allow")
        $Acl.SetAccessRule($Ar)
        Set-Acl $targetDir $Acl

    }

    

    if (test-path ($targetDir+"\active.dat")) {

        # active.dat is always updated                
        Remove-Item ($targetDir+"\active.dat") | Out-Null
        
    } 


    if (Test-IfCopyFile -sourcefile ($sourceDir+"\Transformations.xml") -targetfile ($targetDir+"\Transformations.xml") -ForceUpdate:$ForceUpdateWMSConfig) {
        Write-Verbose ("Updating {0}" -f ($targetDir+"\Transformations.xml"))
        Copy-Item ($sourceDir+"\Transformations.xml") $targetDir -Force | Out-Null
    }


    $lines = Get-Content -Path ($sourceDir+"\active.dat")

    $mpath = "";
    $mname = "";

    foreach($line in $lines) { 
      if ($mpath -eq "") {
        $mpath = $line
      } else {
        if ($mname -eq "") {
            $mname = $line
            Write-Verbose    "Processing '$mname' on '$mpath'..." 

            Write-Verbose  "'$sourceFolder' -> '$targetFolder'..." 

            $targetFolder = Split-Path ( $mpath.Replace($sourceDir, $targetDir )) -Parent;
            $sourceFolder = Split-Path $mpath -Parent;
            $sourceRoot = $sourceDir + "\" + ($sourceFolder.Replace($sourceDir, "").Split('\\')[1])
            $targetRoot = $targetDir + "\" + ($targetFolder.Replace($targetDir, "").Split('\\')[1])



            if (!(Test-Path $targetRoot)) {
                new-item -ItemType Directory -Force -Path $targetRoot | Out-Null
            }

            $capFile = "Capabilities.xml"        


            if (Test-IfCopyFile -sourcefile ($sourceRoot+"\"+$capFile) -targetfile ($targetRoot+"\"+$capFile) -ForceUpdate:$ForceUpdateWMSConfig) {
                Write-Verbose ("Updating {0}" -f ($targetRoot+"\"+$capFile))
                # Test-Path ($sourceRoot+"\"+$capFile)) {                                            
                Copy-Item ($sourceRoot+"\"+$capFile) $targetRoot -Force | Out-Null
            }


            if (!(Test-Path $targetFolder)) {
                new-item -ItemType Directory -Force -Path $targetFolder | Out-Null
            }

            $milFile = "Layer.mil"        

            # if (Test-Path ($sourceFolder+"\"+$milFile)) {
            if (Test-IfCopyFile -sourcefile ($sourceFolder+"\"+$milFile) -targetfile ($targetFolder+"\"+$milFile) -ForceUpdate:$ForceUpdateWMSConfig) {
                Write-Verbose ("Updating {0}" -f ($sourceFolder+"\"+$milFile))
                Copy-Item ($sourceFolder+"\"+$milFile) $targetFolder -Force | Out-Null
            }

        

            ($targetFolder + "\" + $milFile) | out-file -Append ($targetDir+"\Active.dat") -Encoding utf8

            $milFile = "Layer.dat"        

            #if (Test-Path ($sourceFolder+"\"+$milFile)) {
            if (Test-IfCopyFile -sourcefile ($sourceFolder+"\"+$milFile) -targetfile ($targetFolder+"\"+$milFile) -ForceUpdate:$ForceUpdateWMSConfig) {
                Write-Verbose ("Updating {0}" -f ($sourceFolder+"\"+$milFile))
                Copy-Item ($sourceFolder+"\"+$milFile) $targetFolder -Force | Out-Null
            }


            
            $mname | out-file -Append  ($targetDir+"\Active.dat") -Encoding utf8
        
        




            $mname = ""
            $mpath = ""
        } else {
            Write-Warning "Name and path already set! Clearing both"
            $mpath = "";
            $mname = "";
        }
      }
    }

    # http://stackoverflow.com/questions/5596982/using-powershell-to-write-a-file-in-utf-8-without-the-bom
    $MyFile = Get-Content ($targetDir+"\Active.dat")
    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($False)
    [System.IO.File]::WriteAllLines(($targetDir+"\Active.dat"), $MyFile, $Utf8NoBomEncoding)


}


Function RunTrimbleNIS {
    
    Param(
       [Parameter(Mandatory=$True)][string]$TrimbleConfigPath,
       [Parameter(Mandatory=$True)][string]$TrimbleExecutablePath,      
      [string]$TrimbleArguments = ""      
    )

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $TrimbleExecutablePath
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = '-c "'+ $TrimbleConfigPath+'" ' + $TrimbleArguments
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    if ($p.ExitCode -ne 0) {
        $VerbosePreference = $oldverbose
        return $p.ExitCode
    }
    return 0
}


if ($UpdateWMSConfig) {
    if ($ForceUpdateWMSConfig)  {
        UpdateWMSConfig -sourceDir $WMSSourcePath -targetDir $WMSTargetPath  -ForceUpdateWMSConfig
    } else {
        UpdateWMSConfig -sourceDir $WMSSourcePath -targetDir $WMSTargetPath  
    }
}


if ($RunTrimbleNIS) {
    $exitcode = RunTrimbleNIS -TrimbleConfigPath $TrimbleConfigPath -TrimbleExecutablePath $TrimbleExecutablePath -TrimbleArguments $TrimbleArguments
}


$VerbosePreference = $oldverbose
exit $exitcode
# SIG # Begin signature block
# MIINNwYJKoZIhvcNAQcCoIINKDCCDSQCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUHrN2qZDqxmwYRP+bQoF8IPO/
# XbqgggqTMIIFFzCCA/+gAwIBAgITLQAAAvZBJVsiSnHa3wAAAAAC9jANBgkqhkiG
# 9w0BAQsFADBWMRQwEgYKCZImiZPyLGQBGRYEc2lzZTEZMBcGCgmSJomT8ixkARkW
# CW50c2VydmVyMjEjMCEGA1UEAxMaQVMgVGFsbGlubmEgVmVzaSBPbmxpbmUgQ0Ew
# HhcNMTYwMzE0MTIzMDQyWhcNMjEwMzEzMTIzMDQyWjBxMRQwEgYKCZImiZPyLGQB
# GRYEc2lzZTEZMBcGCgmSJomT8ixkARkWCW50c2VydmVyMjEOMAwGA1UECxMFVFZF
# U0kxFzAVBgNVBAsTDkFkbWluaXN0cmF0b3JzMRUwEwYDVQQDEwxBRE0gU2lpbSBB
# dXMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC7JxaBQP70kdl9wu5K
# FTIxSVMFXYauJy/jWXKARXTC3ntzHvz1tFIhySL0+8XedvlcXKEtlscLokMiqbfE
# 2U6EMi5WrDnwQDk+PjEw7szlBWMBrwwwnYrHveZyFuMLQWHDmfMvCmXip76+Gdm0
# XFt0Tl37BmhDd9SMIcGbtecrgzxMXMJBqTYMkXyvSdzH+WAQQyxiSrogji+RpUeE
# AeWuilclec6suByym38mQa79Qw8wPD8qaw237gpkmqF9Jb5L84eU8pUnceANtDsF
# y+TyBRYRjOXNOLp59+vKMWGiU4gkWuTx5wojDz8bt/IsCtXH9tKeS8y1nya8t35W
# IsPhAgMBAAGjggHBMIIBvTA9BgkrBgEEAYI3FQcEMDAuBiYrBgEEAYI3FQiG6ac7
# gsXLWPGRAoO5u3qDg6dAgW2GycdThPeUPwIBZAIBAzATBgNVHSUEDDAKBggrBgEF
# BQcDAzAOBgNVHQ8BAf8EBAMCB4AwGwYJKwYBBAGCNxUKBA4wDDAKBggrBgEFBQcD
# AzAdBgNVHQ4EFgQU6U4LGEbZy0iN05WqXEQsROBbC/swHwYDVR0jBBgwFoAUEWar
# MjEMiM2zLWYVrFQgFOCyF1EwVAYDVR0fBE0wSzBJoEegRYZDaHR0cDovL2NhLm50
# c2VydmVyMi5zaXNlL3BraS9BUyUyMFRhbGxpbm5hJTIwVmVzaSUyME9ubGluZSUy
# MENBLmNybDB3BggrBgEFBQcBAQRrMGkwZwYIKwYBBQUHMAKGW2h0dHA6Ly9jYS5u
# dHNlcnZlcjIuc2lzZS9wa2kvTG9naXN0aWMubnRzZXJ2ZXIyLnNpc2VfQVMlMjBU
# YWxsaW5uYSUyMFZlc2klMjBPbmxpbmUlMjBDQS5jcnQwKwYDVR0RBCQwIqAgBgor
# BgEEAYI3FAIDoBIMEGFkbXNpaW1AdHZlc2kuZWUwDQYJKoZIhvcNAQELBQADggEB
# AEuBQyWG2nOI4gT6JhUl3l/kWEOlP73xD9wGA2zzYnToqQSh031FWDJmRhf5nJOL
# yRerw9pyMicovBvgYraEw+duJTGPbZT20gjO3v6iBwZUyjUd6qN3Ec3lQuSAFq9f
# N6HkzTlb3jK4e71eKneqDqmbkOjFZdT1MT82moTUNvrG0s9Fo2i3qB9BrOedIjDH
# HkUDbo9v+Onz1oBA03YlV45E0Z3jGhjAf6kOMXMbNAXKfPmZ/8jtTOeHPHQHhHtZ
# B0U4tHdoyXD2MwsLrOu963kTV//A4MrtB0ZZZNAPlvm7Q4bXxc6WEiMGwjSRTfek
# iHA0sVJzK9NCrRgg3KPX88QwggV0MIIDXKADAgECAhM+AAAAAl0Bz4yIla0tAAAA
# AAACMA0GCSqGSIb3DQEBDQUAMCMxITAfBgNVBAMTGEFTIFRhbGxpbm5hIFZlc2kg
# Um9vdCBDQTAeFw0xNTA5MDExNTIwMzNaFw0yNTA5MDExNTMwMzNaMFYxFDASBgoJ
# kiaJk/IsZAEZFgRzaXNlMRkwFwYKCZImiZPyLGQBGRYJbnRzZXJ2ZXIyMSMwIQYD
# VQQDExpBUyBUYWxsaW5uYSBWZXNpIE9ubGluZSBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAK7G17xMJSMfMHWGQtHe7x+kAzg9aWRF1AQ6BSDr3aoQ
# oCjd/u67VLbRFVQBi76bOxvzD/1A4BJUBsgoEsC+FXIaEwsbazt8UtS7/S7FL2b3
# uI3a7DYgqRGX+2xqZDOioPM9JE3NND5Vq5heZlhixn4LfneAlEATwjaLUsaEUaDW
# rsV90panoC9ErKhdvSf4D8/rQWjCiutIDEh44Qy6/yslUUQ/U+wLsV21FPjXF5Lj
# /fzTuWoHfK6kGDeik1mSzuMU4cGc7Ndn1fNWoCXJofj5MkXmO7T8Z6pt0TuemGTq
# 24eF9iBtT1vZ993h6ko3gLWhc064PRb4WiuUovA9F9kCAwEAAaOCAWwwggFoMBAG
# CSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBQRZqsyMQyIzbMtZhWsVCAU4LIXUTCB
# hgYDVR0gBH8wfTB7BggqAwSLL0NZBTBvMDoGCCsGAQUFBwICMC4eLABMAGUAZwBh
# AGwAIABQAG8AbABpAGMAeQAgAFMAdABhAHQAZQBtAGUAbgB0MDEGCCsGAQUFBwIB
# FiVodHRwOi8vQ0EubnRzZXJ2ZXIyLnNpc2UvcGtpL2Nwcy50eHQAMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/
# MB8GA1UdIwQYMBaAFP5bMk121+Q3aJo4TLcCxf2u6/UlMFIGA1UdHwRLMEkwR6BF
# oEOGQWh0dHA6Ly9jYS5udHNlcnZlcjIuc2lzZS9wa2kvQVMlMjBUYWxsaW5uYSUy
# MFZlc2klMjBSb290JTIwQ0EuY3JsMA0GCSqGSIb3DQEBDQUAA4ICAQA72eZ7MwNC
# TMvELWsS8GvG6mQWZt+vP8POIvWZRx9rKd5Rtx8Uul5tQVYKEPgqyAX8S6M7bQBz
# kPXNVwXAdui7JpDr5afLYQ0Z1Vt3OeULWUT2Yh3/bS258Li6AL//r2jLzHSCKocy
# 81sLyyiwOLX7T2cKjUMBoxEViLUxaokeApNyumbrC0LshOeiugZlYuWEPTP07MdK
# VumehJRe9ZJy791AdRw7M8S/E38e6BdlSgNbqPQy8tBGUqG9+J8MXwPK5de8IGXr
# fBt4iPauVeDdVKAjEtTg9IMxzUnHsoRr5s3NQi2NfdVE5pVs6lFsD/BEdmkIMNtu
# +oAx02n7NxO+ysRF7I3vjuIb3ba+lTzybXziBWRUnXmL/s3og/ZAMgECjx9dFQ05
# GkauggbQ5EbjMW2uoJLTEg/Q1T/uCGmXgWdc/9OihI4W90mpwSOgapFuLNF8lhAY
# NxuKdvIA2KNqnnwti96L5LwkffM/Si1JTSSM+kq77tn4OdfSgJdqnnOfmc7HkwBo
# gpWR4iROaFMQaOTfaISian4QiLBKA+4NhE5NCzP0LmDuntNKuBTQbjupr0sOyKvh
# 65aZStbU2kmAfUK9kDRqRaGR/IwD4oWpvP/xnq/UzZXOhiPrHC6m3p2WtAdSlk92
# epzTA8dzmq6mq3CDT1O3x1RMFY4HBHHKgzGCAg4wggIKAgEBMG0wVjEUMBIGCgmS
# JomT8ixkARkWBHNpc2UxGTAXBgoJkiaJk/IsZAEZFgludHNlcnZlcjIxIzAhBgNV
# BAMTGkFTIFRhbGxpbm5hIFZlc2kgT25saW5lIENBAhMtAAAC9kElWyJKcdrfAAAA
# AAL2MAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqG
# SIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3
# AgEVMCMGCSqGSIb3DQEJBDEWBBTKVL/xF4NJ0i5p46ieK7CnHzhI5jANBgkqhkiG
# 9w0BAQEFAASCAQAGmm3I2Uuixqw9RB/vKdD1fm2aHd+OPzmCJ/EJVyI4AZMa1YoB
# OofLfaPYLXiDknr/wRGk+rJD+fAyRYxM8xn1YviFWNtKAWsmkXC90k7aoP/ZwaEI
# kjPitQa76qR3S0A3ZRH9QieO9ACll+/HR+1CgSK8928eApPXkl4xsaO1HHvWF+FO
# yan2m/+fDKkK79EU6N48PJ5PaCJ/snYtzfWjZh7BvRm/6msr3l5k0OudJ4eGh5Gn
# kx1/0m1B9qCgtM3gqwwcosD4IuWRiw+NI67BO8of8rTp0HnrmFo8D+QefRsKJSWT
# oLveJWRL40C23PE/VEUpZLEVVnHJv1C0Yu7G
# SIG # End signature block
