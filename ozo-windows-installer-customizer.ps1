#Requires -Modules Dism,OZOLogger -Version 5.1 -RunAsAdministrator

<#PSScriptInfo
    .VERSION 0.0.1
    .GUID 798c9379-3b13-41c0-a2d9-04c7957dff49
    .AUTHOR Andy Lievertz <alievertz@onezeroone.dev>
    .COMPANYNAME One Zero One
    .COPYRIGHT This script is released under the terms of the GNU Public License ("GPL") version 2.0.
    .TAGS
    .LICENSEURI https://github.com/onezeroone-dev/OZO-Windows-Installer-Customizer/blob/main/LICENSE
    .PROJECTURI https://github.com/onezeroone-dev/OZO-Windows-Installer-Customizer
    .ICONURI
    .EXTERNALMODULEDEPENDENCIES Dism,OZOLogger
    .REQUIREDSCRIPTS
    .EXTERNALSCRIPTDEPENDENCIES
    .RELEASENOTES https://github.com/onezeroone-dev/OZO-Windows-Installer-Customizer/blob/main/CHANGELOG.md
    .PRIVATEDATA
#>

<# 
    .SYNOPSIS
    See description.
    .DESCRIPTION
    Customizes the Windows installer ISO based on a JSON configuration file containing parameters for OS, version, edition, and features. It enables automation with an Answer File, can include custom media (wallpapers, logos, etc.), and can remove undesired AppX packages
    .PARAMETER Configuration
    The path to the JSON configuration file. Defaults to ozo-windows-installer-customizer.json in the same directory as this script.
    .PARAMETER Nocleanup
    Do not clean up the temporary file assets. Mostly used for testing and debugging.
    .EXAMPLE
    ozo-windows-installer-customizer -Configuration "C:\Imaging\Configuration\ozo-windows-installer-customizer.json"
    .LINK
    https://github.com/onezeroone-dev/OZO-Windows-Installer-Customizer/blob/main/README.md
    .NOTES
    Run this script as Administrator.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false,HelpMessage="The path to the JSON configuration file")][String]$Configuration = (Join-Path -Path $PSScriptRoot -ChildPath "ozo-windows-installer-customizer.json"),
    [Parameter(HelpMessage="Do not clean up the temporary file assets")][Switch]$NoCleanup
)

# Classes
Class OWICMain {
    # PROPERTIES: Booleans, Strings, Longs
    [Boolean] $Validates = $true
    [Long]    $tempFree  = $null
    [String]  $jsonPath  = $null
    # PROPERTIES: PSCustomObjects
    [PSCustomObject] $Json      = $null
    [PSCustomObject] $ozoLogger = (New-OZOLogger)
    # PROPERTIES: Lists
    [System.Collections.Generic.List[String]] $Editions = @(
        "Home",
        "Home N",
        "Home Single Language",
        "Education",
        "Education N",
        "Pro",
        "Pro N",
        "Pro Education",
        "Pro Education N",
        "Pro for Workstations",
        "Pro N for Workstations",
        "Enterprise",
        "Enterprise N",
        "Enterprise Evaluation",
        "Enterprise N Evaluation"
        "Standard Evaluation",
        "Standard Evaluation (Desktop Experience)",
        "Datacenter Evaluation",
        "Datacenter Evaluation (Desktop Experience)"
    )
    [System.Collections.Generic.List[PSCustomObject]] $Jobs = @()
    # METHODS
    # Constructor method
    OWICMain($Configuration,$NoCleanup) {
        # Set Properties
        $this.jsonPath  = $Configuration
        # Declare ourselves to the world
        $this.ozoLogger.Write("Starting process.","Information")
        # Call ValidateEnvironment to set Validates
        If (($this.ValidateConfiguration() -And $this.ValidateEnvironment()) -eq $true) {
            # Iterate through the enabled jobs in the JSON configuration
            ForEach($jobJson in ($this.Json.Jobs | Where-Object {$_.enabled -eq $true})) {
                # Process the job object
                # Add OscdimgPath, tempDir, and tempFree to the job object
                Add-Member -InputObject $jobJson -MemberType NoteProperty -Name "OscdimgPath" -Value $this.Json.Paths.OscdimgPath
                Add-Member -InputObject $jobJson -MemberType NoteProperty -Name "tempDir" -Value $this.Json.Paths.tempDir
                Add-Member -InputObject $jobJson -MemberType NoteProperty -Name "noCleanup" -Value $NoCleanup
                Add-Member -InputObject $jobJson -MemberType NoteProperty -Name "tempFree" -Value $this.tempFree
                # Add this job to the jobs list
                $this.Jobs.Add([OWICJob]::new($jobJson))
            }
            # Iterate through the valid jobs
            ForEach ($Job in ($this.Jobs | Where-Object {$_.Validates -eq $true})) {
                # Call the CustomizeISO method
                $Job.CustomizeISO()
            }
        } Else {
            # Configuration and environment do not validate
            $this.Validates = $false
        }
        # Call the report method
        $this.Report()
        # Finish
        $this.ozoLogger.Write("Process complete.","Information")
    }
    # JSON validation method
    Hidden [Boolean] ValidateConfiguration() {
        # Control variable
        [Boolean] $Return = $true
        # Determine if the JSON file exists
        If ((Test-Path $this.jsonPath) -eq $true) {
            # File exists; try to convert it from JSON
            Try {
                $this.Json = (Get-Content $this.jsonPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
                # Success
            } Catch {
                # Failure
                $this.ozoLogger.Write("Invalid JSON.","Error")
                $Return = $false
            }
        } Else {
            # File does not exist
            $this.ozoLogger.Write("Configuration file does not exists or is not accessible.","Error")
            $Return = $false
        }
        # Return
        return $Return
    }
    # Paths validation method
    Hidden [Boolean] ValidateEnvironment() {
        # Control variable
        [Boolean] $Return = $true
        # Local variables
        [String] $tempDrive = $null
        # Scrutinize TempDir; determine if the path contains spaces
        If ($this.Json.Paths.TempDir -Match " ") {
            # Found spaces
            $this.ozoLogger.Write("Path to temporary directory cannot contain spaces. This is a limitation of the Microsoft oscdimg.exe command.","Error")
            $Return = $false
        }
        # Determine if TempDir exists
        Try {
            Test-Path -Path $this.Json.Paths.TempDir -ErrorAction Stop
            # Success; get statistics
            $tempDrive = (Get-Item $this.Json.Paths.TempDir).PSDrive.Name
            $this.tempFree = (Get-Volume -DriveLetter $tempDrive).SizeRemaining
            # Determine if TempDir drive is fixed
            If ((Get-Volume -DriveLetter $tempDrive).DriveType -ne "Fixed") {
                # Disk is not fixed
                $this.ozoLogger.Write("Temporary directory is not on a fixed drive.","Error")
                $Return = $false
            }
        } Catch {
            # Path does not exist
            $this.ozoLogger.Write("Temporary directory does not exist.","Error")
            $Return = $false
        }
        # Determine if oscdimg.exe is missing
        Try {
            Test-Path -Path $this.Json.Paths.OscdimgPath -ErrorAction Stop
            # Success
        } Catch {
            # Failure
            $this.ozoLogger.Write("Did not find oscdimg.exe.","Error")
            $Return = $false
        }
        # Return
        return $Return
    }
    # Report class
    [Void] Report() {
        # Determine if any jobs were processed
        If ($this.Jobs.Count -gt 0) {
            # At least one job was processed; determine if there were any successes
            If (($this.Jobs | Where-Object {$_.Success -eq $true}).Count -gt 0) {
                # At least one job was successful; report names
                $this.ozoLogger.Write(("Successfully processed the following jobs:`r`n" + (($this.Jobs | Where-Object {$_.Success -eq $true}).Json.Name -Join("`r`n"))),"Information")
                # Iterate on the success jobs
                ForEach ($successJob in ($this.Jobs | Where-Object {$_.Success -eq $true})) {
                    $this.ozoLogger.writeOutput = $false
                    $this.ozoLogger.Write(("The " + $successJob.Json.Name + " job succeeded with the following messages:`r`n" + ($successJob.Messages -Join("`r`n"))),"Information")
                    $this.ozoLogger.writeOutput = $true
                }
            }
            # Determine if there were any failures
            If (($this.Jobs | Where-Object {$_.Success -eq $false}).Count -gt 0) {
                # At least one job failed; report names
                $this.ozoLogger.Write(("The following jobs failed:`r`n" + (($this.Jobs | Where-Object {$_.Success -eq $false}).Json.Name -Join("`r`n"))),"Warning")
                # Iterate
                ForEach ($failureJob in ($this.Jobs | Where-Object {$_.Success -eq $false})) {
                    $this.ozoLogger.writeOutput = $false
                    $this.ozoLogger.Write(("The " + $failureJob.Json.Name + " job failed with the following messages:`r`n" + ($failureJob.Messages -Join("`r`n"))),"Warning")
                    $this.ozoLogger.writeOutput = $true
                }
            }
            # Report re: additional messages.
            $this.ozoLogger.Write("Please see the One Zero One Windows Event Provider Log for additional detail. If you have not installed the One Zero One Windows Event Provider, messages can be found in the Microsoft Windows PowerShell Event Log Provider under event ID 4100.","Information")
        } Else {
            # No jobs were processed
            $this.ozoLogger.Write("Processed zero jobs.","Warning")
        }
    }
}

Class OWICJob {
    # PROPERTES: Boolean, Long, String, PSCUstomObject
    [Boolean] $Validates     = $true
    [Boolean] $Success       = $true
    [String]  $dvdDir        = $null
    [String]  $iconPath      = $null
    [String]  $jobTempDir    = $null
    [String]  $logoPath      = $null
    [String]  $mountDir      = $null
    [String]  $mountDrive    = $null
    [String]  $OscdimgPath   = $null
    [String]  $targetISOPath = $null
    [String]  $wallpaperPath = $null
    [String]  $wimDir        = $null
    # PROPERTIES: PSCUstomObject
    [PSCustomObject] $Json   = $null
    # PROPERTIES: List
    [System.Collections.Generic.List[String]] $Messages = @()
    # METHODS
    # Constructor method
    OWICJob($Json) {
        # Set properties
        $this.Json       = $Json
        $this.jobTempDir = (Join-Path -Path $this.Json.tempDir -ChildPath ((New-Guid).Guid + "-ozo-windows-installer-customizer"))
        # Declare ourselves to the world
        $this.Messages.Add("Processing job.")
        # Call ValidateJob to set Validates
        If ($this.ValidateJob() -eq $true) {
            # Job validated
            $this.Messages.Add("Job validates.")
            $this.Validates = $true
        } Else {
            # Job did not validate
            $this.Messages.Add("Job does not validate.")
            $this.Validates = $false
            $this.Success   = $false
        }
    }
    # Validate job method
    Hidden [Boolean] ValidateJob() {
        # Control variable
        [Boolean] $Return = $true
        # Local variables
        [Xml] $answerXML = $null
        # Determine if Name is set
        If ([String]::IsNullOrEmpty($this.Json.Name) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing Name.")
            $Return = $false
        }
        # Determine if OSName is set
        If ([String]::IsNullOrEmpty($this.Json.OSName) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing OSName.")
            $Return = $false
        }
        # Determine if Version is set
        If ([String]::IsNullOrEmpty($this.Json.Version) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing Version.")
            $Return = $false
        }
        # Determine if Edition is set
        If ([String]::IsNullOrEmpty($this.Json.Edition) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing Edition.")
            $Return = $false
        }
        # Determine if Feature is set
        If ([String]::IsNullOrEmpty($this.Json.Feature) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing Feature.")
            $Return = $false
        }
        # Determine if Build is set
        If ([String]::IsNullOrEmpty($this.Json.Build) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing Build.")
            $Return = $false
        }
        # Determine if answerPath is set
        If ([String]::IsNullOrEmpty($this.Json.Files.answerPath) -eq $true) {
            # Not set; warn
            $this.Messages.Add("Job configuration is missing answerPath.")
            $Return = $false
        } Else {
            # Set; Determine that file exists
            If ((Test-Path -Path $this.Json.Files.answerPath) -eq $true){
                # File exists; try if XML is valid
                Try {
                    $answerXml = [Xml](Get-Content -Path $this.Json.Files.answerPath -ErrorAction Stop) | Out-Null
                    # Success (valid XML); set logoPath
                    $this.logoPath = (($answerXml.unattend.settings | Where-Object {$_.pass -eq "specialize"}).component | Where-Object {$_.name -eq "Microsoft-Windows-Shell-Setup"}).OEMInformation.Logo
                    # Determine if an icon is specified
                    $this.iconPath = (($answerXml.unattend.settings | Where-Object {$_.pass -eq "oobeSystem"}).component | Where-Object {$_.name -eq "Microsoft-Windows-Shell-Setup"}).Themes.BrandIcon
                    # Determine if a wallpaper is specified
                    $this.wallpaperPath = (($answerXml.unattend.settings | Where-Object {$_.pass -eq "oobeSystem"}).component | Where-Object {$_.name -eq "Microsoft-Windows-Shell-Setup"}).Themes.DesktopBackground
                } Catch {
                    # Failure (invalid XML)
                    $this.Messages.Add("Answer file contains invalid XML.")
                    $Return = $false
                }
            } Else {
                # File does not exist; error
                $this.Messages.Add("Answer file specified but file not found.")
                $Return = $false
            }
        }
        # Determine if sourceISOPath is set
        If ([String]::IsNullOrEmpty($this.Json.Files.sourceISOPath) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing sourceISOPath.")
        } Else {
            # Set; determine that path does not contain spaces
            If ($this.Json.Files.sourceISOPath -Match " ") {
                # Path contains spaces - oscdimg.exe cannot handle spaces
                $this.Messages.Add("The sourceISOPath contains spaces. Due to a limitation with oscdimg.exe, this path cannot contain spaces.")
                $Return = $false
            } 
            # Determine that file exists
            If ((Test-Path -Path $this.Json.Files.sourceISOPath) -eq $true) {
                # File exists; parse to set targetISOPath
                $this.targetISOPath = (Join-Path -Path (Split-Path -Path $this.Json.Files.sourceISOPath -Parent) -ChildPath ("OZO-" + $this.Json.OSName + "-" + $this.Json.Version + "-" + $this.Json.Edition + "-" + $this.Json.Feature + "-" + $this.Json.Build + ".iso"))
                # Determine if target ISO already exists
                If ((Test-Path -Path $this.targetISOPath) -eq $true) {
                    # Target ISO exists; error
                    $this.Messages.Add("Target ISO exists; skipping.")
                    $Return = $false
                }
                # File exists; determine if the disk has enough space for this job
                If ($this.Json.tempFree -lt ((Get-Item -Path $this.Json.Files.sourceISOPath).Length * 4)) {
                    # Disk does not have enough space
                    $this.Messages.Add("Drive does not have enough free space; requires size of ISO x 4.")
                    $Return = $false
                }
            } Else {
                # File does not exist; error
                $this.Messages.Add("Source ISO specified but file not found.")
                $Return = $false
            }
        }
        # Determine if logoPath is set
        If ([String]::IsNullOrEmpty($this.Json.Files.logoPath) -eq $false) {
            # Set; determine that file exists
            If((Test-Path -Path $this.Json.Files.logoPath) -eq $false) {
                # File does not exist; warn
                $this.Messages.Add("Logo path specified but file not found.")
                $Return = $false
            }
        }
        # Determine if iconPath is set
        If ([String]::IsNullOrEmpty($this.Json.Files.iconPath) -eq $false) {
            # Set; determine that file exists
            If((Test-Path -Path $this.Json.Files.iconPath) -eq $false) {
                # File does not exist; warn
                $this.Messages.Add("Icon path specified but file not found.")
                $Return = $false
            }
        }
        # Determine if wallpaperPath is set
        If ([String]::IsNullOrEmpty($this.Json.Files.wallpaperPath) -eq $false) {
            # Set; determine that file exists
            If((Test-Path -Path $this.Json.Files.wallpaperPath) -eq $false) {
                # File does not exist; warn
                $this.Messages.Add("Wallpaper path specified but file not found.")
                $Return = $false
            }
        }
        # Determine if any drivers directories are set
        If ($this.Json.Drivers.Count -gt 0) {
            # At least one drivers directory is set; iterate
            ForEach ($Driver in $this.Json.Drivers) {
                # Determine if the path is not found
                If ((Test-Path -Path $Driver) -eq $false) {
                    # Path is not found
                    $this.Messages.Add(("Missing drivers directory " + $Driver + "."))
                    $Return = $false
                }
            }
        } Else {
            # No drivers directories are set
            $this.Messages.Add("No drivers directories specified.")
        }
        # Determine if any AppXProvisionedPackages are set
        If($this.Json.removeAppxProvisionedPackages.Count -eq 0) {
            # No AppXPackages set
            $this.Messages.Add("No AppxPackages specified.")
        }
        # Return
        return $Return
    }
    # Customize ISO method
    [Void] CustomizeISO() {
        # Call all methods in order to set Success
        $this.Success = (
            $this.CreateJobTempDirs() -And
            $this.MountISO() -And
            $this.CopyISO() -And
            $this.MoveWIM() -And
            $this.ExportIndex() -And
            $this.MountWIM() -And
            $this.CopyMediaAssets() -And
            $this.AddDrivers() -And
            $this.RemoveAppxPackages() -and
            $this.DismountWIM() -And
            $this.CopyAnswerFile -And
            $this.WriteISO()
        )
        # Call Cleanup to clean up temporary file assets
        $this.Cleanup()
    }
    # Create job temporary directories method
    Hidden [Boolean] CreateJobTempDirs() {
        # Control variable
        [Boolean] $Return = $true
        # Attempt to create jobTempDir
        Try {
            New-Item -ItemType Directory -Path $this.jobTempDir -ErrorAction Stop
            # Success; set paths
            $this.dvdDir   = (Join-Path -Path $this.jobTempDir -ChildPath "DVD")
            $this.wimDir   = (Join-Path -Path $this.jobTempDir -ChildPath "WIM")
            $this.mountDir = (Join-Path -Path $this.jobTempDir -ChildPath "Mount")
            # Try to create paths
            Try {
                New-Item -ItemType Directory -Path $this.dvdDir -Force -ErrorAction Stop
                New-Item -ItemType Directory -Path $this.wimDir -Force -ErrorAction Stop
                New-Item -ItemType Directory -Path $this.mountDir -Force -ErrorAction Stop
                # Success
            } Catch {
                # Failure
                $this.Messages.Add(("Unable to create one or more subdirectories of " + $this.jobTempDir))
                $Return = $false
            }
        } Catch {
            # Failure
            $this.Messages.Add("Failed to create temporary job directory")
            $Return = $false
        }

        # Return
        return $Return
    }
    # Mount ISO method
    Hidden [Boolean] MountISO() {
        # Control variable
        [Boolean] $Return = $true
        Try {
            Mount-DiskImage -ImagePath $this.Json.Files.sourceISOPath -ErrorAction Stop
            # Success; get the drive letter
            $this.mountDrive = (Get-DiskImage $this.Json.Files.sourceISOPath -ErrorAction Stop | Get-Volume -ErrorAction Stop).DriveLetter
        } Catch {
            # Failure
            $this.Messages.Add("Failed to mount source ISO")
            $Return = $false
        }
        # Return
        return $Return
    }
    # Copy ISO method
    Hidden [Boolean] CopyISO() {
        # Control variable
        [Boolean] $Return = $true
        Try {
            Copy-Item -Path ($this.mountDrive + ":\*") -Recurse -Destination ($this.dvdDir + "\") -ErrorAction Stop
            #Success
        } Catch {
            # Failure
            $this.Messages.Add("Failed to copy ISO contents to the DVD directory")
            $Return = $false
        }
        # Return
        return $Return
    }
    # Move WIM method
    Hidden [Boolean] MoveWIM() {
        # Control variable
        [Boolean] $Return = $true
        Try {
            Move-Item -Path (Join-Path -Path $this.dvdDir -ChildPath "sources\install.wim") -Destination ($this.wimDir + "\") -ErrorAction Stop
            #Success
        } Catch {
            # Failure
            $this.Messages.Add("Failed to move the WIM")
            $Return = $false
        }
        # Return
        return $Return
    }
    # Export index method
    Hidden [Boolean] ExportIndex() {
        # Control variable
        [Boolean] $Return    = $true
        [String]  $IndexName = ($this.Json.OSName + " " + $this.Json.Version + " " + $this.Json.Edition)
        Try {
            Export-WindowsImage -SourceName $IndexName -SourceImagePath (Join-Path -Path $this.wimDir -ChildPath "install.wim") -DestinationImagePath (Join-Path -Path $this.dvdDir -ChildPath "sources\install.wim") -ErrorAction Stop
            #Success
        } Catch {
            # Failure
            $this.Messages.Add(("Failed to export the " + $IndexName + " index"))
            $Return = $false
        }
        # Return
        return $Return
    }
    # Mount WIM method
    Hidden [Boolean] MountWIM() {
        # Control variable
        [Boolean] $Return = $true
        Try {
            Mount-WindowsImage -Path $this.mountDir -ImagePath (Join-Path -Path $this.dvdDir -ChildPath "sources\install.wim") -Index 1 -ErrorAction Stop
            #Success
        } Catch {
            # Failure
            $this.Messages.Add("Failed to mount WIM")
            $Return = $false
        }
        # Return
        return $Return
    }
    # Copy media assets method
    Hidden [Boolean] CopyMediaAssets() {
        # Control variable
        [Boolean] $Return = $true
        # Determine if any of the three media assets were defined in the XML
        If (([String]::IsNullOrEmpty($this.logoPath) -eq $false) -Or ([String]::IsNullOrEmpty($this.iconPath) -eq $false) -Or ([String]::IsNullOrEmpty($this.wallpaperPath) -eq $false)) {
            # At least one of logoPath, iconPath, or wallpaperPath were found in the XML; try to create the OEM directory
            Try {
                New-Item -ItemType Directory -Path (Join-Path -Path $this.mountDir -ChildPath "Windows\System32\OEM") -ErrorAction Stop
                # Success; determine if logoPath was set in the XML
                If ([String]::IsNullOrEmpty($this.logoPath) -eq $false) {
                    # logoPath was set in the XML; determine if the logoPath is set in the job configuration and the file exists
                    If ([String]::IsNullOrEmpty($this.Json.Files.logoPath) -eq $false -And (Test-Path -Path $this.Json.Files.logoPath) -eq $true) {
                        # logoPath is set in the job configuration and the file exists; try to copy
                        Try {
                            Copy-Item -Path $this.Json.Files.logoPath -Destination (Join-Path -Path $this.mountDir -ChildPath (Join-Path -Path "Windows\System32\OEM" -ChildPath $this.logoPath)) -ErrorAction Stop
                            #Success
                        } Catch {
                            # Failure
                            $this.Messages.Add("Failed to copy logo file.")
                            $Return = $false
                        }
                    } Else {
                        $this.Messages.Add("Logo is specified in the Autounattend XML but (a) not specified in the job configuration or (b) specified in the job configuration but the file is missing or not accessible.")
                        $Return = $false
                    }
                } Else {
                    $this.Messages.Add("No logo path found in the Autounattend XML.")
                }
                # Determine if iconPath is set
                If ([String]::IsNullOrEmpty($this.iconPath) -eq $false) {
                    # iconPath was set in the XML; determine if the iconPath is set in the job configuration and the file exists
                    If ([String]::IsNullOrEmpty($this.Json.Files.iconPath) -eq $false -And (Test-Path -Path $this.Json.Files.iconPath) -eq $true) {
                        # logoPath is set in the job configuration and the file exists; try to copy
                        Try {
                            Copy-Item -Path $this.Json.Files.iconPath -Destination (Join-Path -Path $this.mountDir -ChildPath (Join-Path -Path "Windows\System32\OEM" -ChildPath $this.iconPath)) -ErrorAction Stop
                            #Success
                        } Catch {
                            # Failure
                            $this.Messages.Add("Failed to copy icon file.")
                            $Return = $false
                        }
                    } Else {
                        $this.Messages.Add("Icon is specified in the Autounattend XML but (a) not specified in the job configuration or (b) specified in the job configuration but the file is missing or not accessible.")
                        $Return = $false
                    }
                } Else {
                    $this.Messages.Add("No icon path found in the Autounattend XML.")
                }
                # Determine if wallpaperPath is set
                If ([String]::IsNullOrEmpty($this.wallpaperPath) -eq $false) {
                    # wallpaperPath was set in the XML; determine if the wallpaperPath is set in the job configuration and the file exists
                    If ([String]::IsNullOrEmpty($this.Json.Files.wallpaperPath) -eq $false -And (Test-Path -Path $this.Json.Files.wallpaperPath) -eq $true) {
                        # logoPath is set in the job configuration and the file exists; try to copy
                        Try {
                            Copy-Item -Path $this.Json.Files.wallpaperPath -Destination (Join-Path -Path $this.mountDir -ChildPath (Join-Path -Path "Windows\System32\OEM" -ChildPath $this.wallpaperPath)) -ErrorAction Stop
                            #Success
                        } Catch {
                            # Failure
                            $this.Messages.Add("Failed to copy logo file.")
                            $Return = $false
                        }
                    } Else {
                        $this.Messages.Add("Wallpaper is specified in the Autounattend XML but (a) not specified in the job configuration or (b) specified in the job configuration but the file is missing or not accessible.")
                        $Return = $false
                    }
                } Else {
                    $this.Messages.Add("No wallpaper path found in the Autounattend XML.")
                }
            } Catch {
                $this.Messages.Add("Unable to create OEM directory for media assets.")
                $Return = $false
            }
        } Else {
            # No media assets were set
            $this.Messages.Add("No media assets were specified.")
        }
        # Return
        return $Return
    }
    # Add drivers method
    Hidden [Boolean] AddDrivers() {
        # Control variable
        [Boolean] $Return = $true
        # Iterate through the Models
        ForEach ($Driver in $this.Drivers) {
            # Try to add drivers
            Try {
                Add-WindowsDriver -Path $this.mountDir -Driver $Driver -Recurse -ErrorAction Stop
                #Success
            } Catch {
                # Failure
                $this.Messages.Add(("Failed to add " + $Driver + " to image."))
                $Return = $false
            }
        }
        # Return
        return $Return
    }
    # RemoveAppxPackages method
    Hidden [Boolean] RemoveAppxPackages() {
        # Control variable
        [Boolean] $Return = $true
        # Determine if there are any packages to be removed
        If ($this.Json.removeAppxProvisionedPackages.Count -gt 0) {
            # One or more packages have been identified for removal; iterate through them
            ForEach ($AppxPackage in (Get-AppxProvisionedPackage -Path $this.mountDir)) {
                # Determine if this package appears in the image
                If ($this.removeAppxProvisionedPackages -Contains $AppxPackage.DisplayName) {
                    # Package appears in the image; try to remove
                    Try {
                        Remove-AppXProvisionedPackage -Path $this.mountDir -PackageName $AppxPackage.PackageName -ErrorAction Stop
                        # Success
                    } Catch {
                        # Failure
                        $this.Messages.Add(("Unable to remove the " + $AppxPackage.DisplayName + " package from the image."))
                    }
                }
            }
        } Else {
            $this.Messages.Add("No AppxPackages to remove.")
        }
        # Return
        return $Return
    }
    # Unmount WIM method
    Hidden [Boolean] DismountWIM() {
        # Control variable
        [Boolean] $Return = $true
        # Try to dismount the WIM
        Try {
            Dismount-WindowsImage -Path $this.mountDir -Save -ErrorAction Stop
            #Success
        } Catch {
            # Failure
            $this.Messages.Add("Failed to dismount the WIM.")
            $Return = $false
        }
        # Return
        return $Return
    }
    # Copy answer file method
    Hidden [Boolean] CopyAnswerFile() {
        # Control variable
        [Boolean] $Return = $true
        Try {
            Copy-Item -Path $this.Json.Files.answerPath -Destination (Join-Path -Path $this.dvdDir -ChildPath "Autounattend.xml") -ErrorAction Stop
            #Success
        } Catch {
            # Failure
            $this.Messages.Add("Failed to copy Answer file.")
            $Return = $false
        }
        # Return
        return $Return
    }
    # Write ISO method
    Hidden [Boolean] WriteISO() {
        # Control variable
        [Boolean] $Return = $true
        # Try to write the ISO
        Try {
            Start-Process -NoNewWindow -Wait -FilePath $this.Json.OscdimgPath -ArgumentList ('-u2 -udfver102 -t -l' + [System.IO.Path]::GetFileNameWithoutExtension($this.targetISOPath) + ' -b' + (Join-Path -Path $this.dvdDir -ChildPath "efi\microsoft\boot\efisys.bin") + ' ' + ($this.dvdDir + "\") + ' ' + $this.targetISOPath)
            #Success
        } Catch {
            # Failure
            $this.Messages.Add("Failed to write ISO.")
            $Return = $false
        }
        # Return
        return $Return
    }
    # Cleanup method
    Hidden [Void] Cleanup() {
        # Determine if there are any mounted images
        If ((Get-WindowsImage -Mounted).Count -gt 0 -And (Get-WindowsImage -Mounted) -Contains $this.mountDir) {
            # There are mounted images and one of them contains mountDir; try to unmount
            Try {
                Dismount-WindowsImage -Path $this.MountDir -Discard -ErrorAction Stop
                # Success;
            } Catch {
                $this.Messages.Add("Unable to unmount image.")
            }
        }
        # Determine if the ISO is still mounted
        If ($null -ne (Get-DiskImage $this.Json.Files.sourceISOPath | Get-Volume).DriveLetter) {
            # ISO is still mounted; try to dismount
            Try {
                Dismount-DiskImage -ImagePath $this.Json.Files.sourceISOPath -ErrorAction Stop
                # Success
            } Catch {
                # Failure
                $this.Messages.Add("Unable to unmount ISO.")
            }
        }
        # Determine if operator did not request NoCleanup
        If ($this.Json.noCleanup -eq $false) {
            # Operator did not request NoCleanup; try to remove the jobTempDir
            Try {
                Remove-Item -Recurse -Force -Path $this.jobTempDir -ErrorAction Stop
            } Catch {
                $this.Messages.Add(("Unable to remove job temporary directory " + $this.jobTempDir + ". Please delete manually."))
            }
        }
    }
}

# MAIN
[OWICMain]::new($Configuration,$NoCleanup) | Out-Null
