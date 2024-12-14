#Requires -Modules Dism,OZOLogger -RunAsAdministrator

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
    .EXTERNALMODULEDEPENDENCIES
    .REQUIREDSCRIPTS
    .EXTERNALSCRIPTDEPENDENCIES
    .RELEASENOTES https://github.com/onezeroone-dev/OZO-Windows-Installer-Customizer/blob/main/CHANGELOG.md
    .PRIVATEDATA
#>

<# 
    .SYNOPSIS
    See description.
    .DESCRIPTION
    Customizes the Windows installer ISO based on a JSON configuration file containing parameters for OS, version, edition, and features. It enabled automation with an Answer File and assist the operator in adding custom media (wallpapers, logos, etc.) and removing undesired AppX packages.
    .PARAMETER Configuration
    The path to the JSON configuration file. Defaults to ozo-windows-installer-customizer.json in the same directory as this script.
    .PARAMETER Nocleanup
    Do not clean up the temporary file assets. Mostly used for testing and debugging.
    .EXAMPLE
    ozo-windows-installer-customizer -Configuration "C:\Scripts\ozo-windows-installer-customizer.json"
    .LINK
    https://github.com/onezeroone-dev/OZO-Windows-Installer-Customizer/blob/main/README.md
    .NOTES
    Requires Administrator privileges.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false,HelpMessage="The path to the JSON configuration file")][String]$Configuration = (Join-Path -Path $PSScriptRoot -ChildPath "ozo-windows-installer-customizer.json")
)

# Classes

Class OWICConfiguration {
    # PROPERTIES: Boolean, String, Long, PSCustomObject
    [Boolean]        $noCleanup = $false
    [Boolean]        $Validates = $true
    [Long]           $tempFree  = $null
    [String]         $jsonPath  = $null
    [PSCustomObject] $Json      = $null
    # Constructor method
    OWICConfiguration($Configuration,$NoCleanup) {
        # Set Properties
        $this.jsonPath  = $Configuration
        $this.noCleanup = $NoCleanup
        # Call ValidateEnvironment to set Validates
        $this.Validates = ($this.ValidateJSON() -And $this.ValidateEnvironment())
    }
    # JSON validation method
    [Boolean] ValidateJSON() {
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
                $Global:owicLogger.Write("Invalid JSON.","Error")
                $Return = $false
            }
        } Else {
            # File does not exist
            $Global:owicLogger.Write("Configuration file does not exists or is not accessible.","Error")
            $Return = $false
        }
        # Return
        return $Return
    }
    # Paths validation method
    [Boolean] ValidateEnvironment() {
        [Boolean] $Return = $true
        # Scrutinize TempDir; determine if the path contains spaces
        If ($this.Json.Paths.TempDir -Match " ") {
            # Found spaces
            $Global:owicLogger.Write("Path to temporary directory cannot contain spaces. This is a limitation of the Microsoft oscdimg.exe command.","Error")
            $Return = $false
        }
        # Determine if TempDir exists
        If ((Test-Path -path $this.Json.TempDir) -eq $true) {
            # Path exists; get statistics
            [String] $tempDrive = (Get-Item $this.Json.Paths.TempDir).PSDrive.Name
            $this.tempFree = (Get-Volume -DriveLetter $tempDrive).SizeRemaining
            # Determine if TempDir drive is fixed
            If ((Get-Volume -DriveLetter $tempDrive).DriveType -ne "Fixed") {
                # Disk is not fixed
                $Global:owicLogger.Write("Temporary directory is not on a fixed drive.","Error")
                $Return = $false
            }
        } Else {
            # Path does not exist
            $Global:owicLogger.Write("Temporary directory does not exist.","Error")
            $Return = $false
        }
        # Determine if oscdimg.exe is missing
        If ((Test-Path -Path $this.Json.Paths.OscdimgPath) -eq $false) {
            # Not found
            $Global:owicLogger.Write("Did not find oscdimg.exe.","Error")
            $Return = $false
        }
        # Return
        return $Return
    }
}

Class OWICMain {
    # PROPERTIES: List
    [System.Collections.Generic.List[PSCustomObject]] $Jobs = @()
    # METHODS
    # Constructor method
    OWICMain() {
        # Iterate through the enabled jobs in the JSON configuration
        ForEach($Job in ($Global:owicConfiguration.Json.Jobs | Where-Object {$_.enabled -eq $true})) {
            # Create an object of the OWICJob class
            $this.Jobs.Add([OWICJob]::new($Job))
        }
        # Iterate through the validated jobs
        ForEach ($Job in ($this.Jobs | Where-Object {$_.Validated -eq $true})) {
            # Call the CustomizeISO method
            $Job.CustomizeISO()
        }
        # Call the report method
        $this.Report()
    }
    # Report class
    [Void] Report() {
        $Global:owicLogger.Write("That's all, folks","Information")
    }
}
Class OWICJob {
    # PROPERTES: Boolean, Long, String, PSCUstomObject
    [Boolean] $Validates     = $true
    [Boolean] $Success       = $true
    [String]  $dvdDir        = $null
    [String]  $jobTempDir    = $null
    [String]  $mountDir      = $null
    [String]  $mountDrive    = $null
    [String]  $targetISOPath = $null
    [String]  $wimDir        = $null
    # PROPERTIES: PSCUstomObject
    [PSCustomObject] $Job    = $null
    # PROPERTIES: List
    [System.Collections.Generic.List[String]]         $Messages = @()
    [System.Collections.Generic.List[PSCustomObject]] $Models   = @()
    # METHODS
    # Constructor method
    OWICJob($Job) {
        # Set properties
        $this.Job = $Job
        $this.jobTempDir = (Join-Path -Path $Global:owicConfiguration.tempDir -ChildPath ((New-Guid).Guid + "-ozo-windows-installer-customizer"))
        # Declare ourselves to the world
        $Global:owicLogger.Write(("Processing job " + $this.Job.Name + "."),"Information")
        # Call ValidateJob to set Validates
        If ($this.ValidateJob() -eq $true) {
            # Job validated
            $Global:owicLogger.Write("Job validates.","Information")
            $this.Validates = $true
        } Else {
            # Job did not validate
            $Global:owicLogger.Write("Job did not validate.","Error")
            $this.Validates = $false
            $this.Success   = $false
        }
    }
    # Validate job method
    [Boolean] ValidateJob() {
        # Control variable
        [Boolean] $Return = $true
        # Determine if Name is set
        If([String]::IsNullOrEmpty($this.Job.Name) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing Name")
            $Return = $false
        }
        # Determine if OSName is set
        If([String]::IsNullOrEmpty($this.Job.OSName) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing OSName")
            $Return = $false
        }
        # Determine if Version is set
        If([String]::IsNullOrEmpty($this.Job.Version) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing Version")
            $Return = $false
        }
        # Determine if Edition is set
        If([String]::IsNullOrEmpty($this.Job.Edition) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing Edition")
            $Return = $false
        }
        # Determine if Feature is set
        If([String]::IsNullOrEmpty($this.Job.Feature) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing Feature")
            $Return = $false
        }
        # Determine if Build is set
        If([String]::IsNullOrEmpty($this.Job.Build) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing Build")
            $Return = $false
        }
        # Determine if answerPath is set
        If([String]::IsNullOrEmpty($this.Job.Files.answerPath) -eq $true) {
            # Not set; warn
            $this.Messages.Add("Job configuration is missing answerPath")
            $Return = $false
        } Else {
            # Set; Determine that file exists
            If((Test-Path -Path $this.Job.Files.answerPath) -eq $true){
                # File exists; try if XML is valid
                Try {
                    [Xml](Get-Content -Path $this.Job.Files.answerPath -ErrorAction Stop) | Out-Null
                    # Success (valid XML)
                } Catch {
                    # Failure (invalid XML)
                    $this.Messages.Add("Answer file contains invalid XML")
                    $Return = $false
                }
            } Else {
                # File does not exist; error
                $this.Messages.Add("Answer file specified but file not found")
                $Return = $false
            }
        }
        # Determine if sourceISOPath is set
        If([String]::IsNullOrEmpty($this.Job.Files.sourceISOPath) -eq $true) {
            # Not set; error
            $this.Messages.Add("Job configuration is missing sourceISOPath")
        } Else {
            # Set; determine that file exists
            If((Test-Path -Path $this.Job.Files.sourceISOPath) -eq $true) {
                # File exists; parse to set targetISOPath
                $this.targetISOPath = (Join-Path -Path (Split-Path -Path $this.Job.Files.sourceISOPath -Parent) -ChildPath ("OZO-" + $this.Job.OSsName + "-" + $this.Job.Version + "-" + $this.Job.Edition + "-" + $this.Job.Feature + "-" + $this.Job.Build + ".iso"))
                # Determine if target ISO already exists
                If ((Test-Path -Path $this.targetISOPath) -eq $true) {
                    # Target ISO exists; error
                    $this.Messages.Add("Target ISO exists; skipping.")
                    $Return = $false
                }
                # File exists; deetermine if the disk has enough space for this job
                If ($Global:owicConfiguration.tempFree -lt ((Get-Item -Path $this.Job.Files.inputIsoPath).Length * 4)) {
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
        If([String]::IsNullOrEmpty($this.Job.Files.logoPath)) {
            # Set; determine that file exists
            If((Test-Path -Path $this.Job.Files.logoPath) -eq $false) {
                # File does not exist; warn
                $this.Messages.Add("Logo path specified but file not found.")
            }
        }
        # Determine if iconPath is set
        If([String]::IsNullOrEmpty($this.Job.Files.iconPath)) {
            # Set; determine that file exists
            If((Test-Path -Path $this.Job.Files.iconPath) -eq $false) {
                # File does not exist; warn
                $this.Messages.Add("Icon path specified but file not found.")
            }
        }
        # Determine if wallpaperPath is set
        If([String]::IsNullOrEmpty($this.Job.Files.wallpaperPath)) {
            # Set; determine that file exists
            If((Test-Path -Path $this.Job.Files.wallpaperPath) -eq $false) {
                # File does not exist; warn
                $this.Messages.Add("Wallpaper path specified but file not found.")
            }
        }        
        # Determine that at least one model is specified
        If($this.Job.Models.Count -gt 0) {
            # At least one model specified; iterate through them
            ForEach($Model in $this.Json.Models) {
                # Create an object of the Model class
                $this.Models.Add([OWICModel]::new($Model))
            }
            # Determine if any of the models failed to validate
            If (($this.Models | Where-Object {$_.Validates -eq $false}).Count -gt 0) {
                # At least one model failed to validate
                $this.Messages.Add("One or more models failed to validate")
                $Return = $false
            }
        } Else {
            # No models specified
            $Global:owicLogger.Add(("No models specified."))
        }
        # check if any AppXProvisionedPackages are specified
        If($this.Job.removeAppxProvisionedPackages.Count -eq 0) {
            # No AppXPackages specified
            $this.Messages.Add(("No AppxPackages specified."))
        }
        # Return
        return $Return
    }
    # Customize ISO method
    [Void] CustomizeISO() {
        # Declare ourselves to the world
        $this.Messages.Add("Starting ISO customization")
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
            $this.UnmountWIM() -And
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
            Mount-DiskImage -ImagePath $this.Job.sourceISOPath -ErrorAction Stop
            # Success; get the drive letter
            $this.mountDrive = (Get-DiskImage $this.Job.sourceISOPath -ErrorAction Stop | Get-Volume -ErrorAction Stop).DriveLetter
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
            $this.Messages.Add("Failed to copy ISO contents to the dvdDir directory")
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
            Move-Item -Path ($this.dvdDir + "\sources\install.wim") -Destination ($this.wimDir + "\") -ErrorAction Stop
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
        [Boolean] $Return = $true
        [String]  $Index  = ($this.Job.OSName + " " + $this.Job.Version + " " + $this.Job.Edition)
        Try {
            Export-WindowsImage -SourceName $Index -SourceImagePath ($this.wimDir + "\install.wim") -DestinationImagePath ($this.dvdDir + "\sources\install.wim") -ErrorAction Stop
            #Success
        } Catch {
            # Failure
            $this.Messages.Add(("Failed to export the " + $Index + " index"))
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
            Mount-WindowsImage -Path $this.mountDir -ImagePath ($this.dvdDir + "\sources\install.wim") -Index 1 -ErrorAction Stop
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
        # Make sure all three assets are defined
        If ([String]::IsNullOrEmpty($this.Job.Files.logoPath) -eq $false -And [String]::IsNullOrEmpty($this.Job.Files.iconPath -eq $false -And [String]::IsNullOrEmpty($this.Job.Files.wallpaperPath -eq $false))) {
            # All three assets are defined
            Try {
                New-Item -ItemType Directory -Path (Join-Path -Path $this.mountDir -ChildPath "Windows\System32\OEM") -ErrorAction Stop
                Copy-Item -Path $this.Job.Files.logoPath -Destination (Join-Path -Path $this.mountDir -ChildPath "Windows\System32\OEM\logo.png") -ErrorAction Stop
                Copy-Item -Path $this.Job.Files.iconPath -Destination (Join-Path -Path $this.mountDir -ChildPath "Windows\System32\OEM\icon.png") -ErrorAction Stop
                Copy-Item -Path $this.Job.Files.wallpaperPath -Destination (Join-Path -Path $this.mountDir -ChildPath "Windows\System32\OEM\wallpaper.png") -ErrorAction Stop
                #Success
            } Catch {
                # Failure
                $this.Messages.Add("Failed to copy media assets")
                $Return = $false
            }
        }
        # Return
        return $Return
    }
    # Add drivers method
    Hidden [Boolean] AddDrivers() {
        # Control variable
        [Boolean] $Return = $true
        # Iterate through the Models
        ForEach ($Model in $this.Models) {
            # Determine if the Model validated
            If ($Model.Validates -eq $true) {
                # Model vaildates; try to add drivers
                Try {
                    Add-WindowsDriver -Path $this.mountDir -Driver $Model.DriversDirectory -Recurse -ErrorAction Stop
                    #Success
                } Catch {
                    # Failure
                    $this.Messages.Add("Failed")
                    $Return = $false
                }
            } Else {
                # Model did not validate
                $this.Messages.Add(("The " + $Model.Name + " model did not validate; skipping"))
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
        If ($this.Job.removeAppxProvisionedPackages.Count -gt 0) {
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
                } Else {
                    # Package does not appear in the image
                    $this.Messages.Add(("Package " + $AppxPackage.DisplayName + " not found in the image."))
                }            
            }
        } Else {
            $this.Messages.Add("No AppxPackages to remove.")
        }
        # Return
        return $Return
    }
    # Unmount WIM method
    Hidden [Boolean] UnmountWIM() {
        # Control variable
        [Boolean] $Return = $true
        Try {
            Dismount-WindowsImage -Path $this.mountDir -Save -ErrorAction Stop
            #Success
        } Catch {
            # Failure
            $this.Messages.Add("Failed to unmount WIM")
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
            Copy-Item -Path $this.answerPath -Destination (Join-Path -Path $this.dvdDir -ChildPath "Autounattend.xml") -ErrorAction Stop
            #Success
        } Catch {
            # Failure
            $this.Messages.Add("Failed to copy Answer file")
            $Return = $false
        }
        # Return
        return $Return
    }
    # Write ISO method
    Hidden [Boolean] WriteISO() {
        # Control variable
        [Boolean] $Return = $true
        Try {
            Start-Process -NoNewWindow -Wait -FilePath $Global:owicConfiguration.OscdimgPath -ArgumentList ('-u2 -udfver102 -t -l' + [System.IO.Path]::GetFileNameWithoutExtension($this.targetISOPath) + ' -b' + (Join-Path -Path $this.dvdDir -ChildPath "efi\microsoft\boot\efisys.bin") + ' ' + ($this.dvdDir + "\") + ' ' + $this.targetISOPath)
            #Success
        } Catch {
            # Failure
            $this.Messages.Add("Failed to write ISO")
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
        If ($null -ne (Get-DiskImage $this.Job.sourceISOPath | Get-Volume).DriveLetter) {
            # ISO is still mounted; try to dismount
            Try {
                Dismount-DiskImage -ImagePath $this.Job.sourceISOPath -ErrorAction Stop
                # Success
            } Catch {
                # Failure
                $this.Messages.Add("Unable to unmount ISO.")
            }
        }
        # Determine if operator did not request NoCleanup
        If ($Global:owicConfiguration.noCleanup -eq $false) {
            # Operator did not request NoCleanup; try to remove the jobTempDir
            Try {
                Remove-Item -Recurse -Force -Path $this.jobTempDir -ErrorAction Stop
            } Catch {
                $this.Messages.Add(("Unable to remove job temporary directory " + $this.jobTempDir + ". Please delete manually."))
            }
        }
    }
}

Class OWICModel {
    # PROPERTIES: Boolean, String
    [Boolean] $Validates        = $true
    [String]  $Name             = $null
    [String]  $DriversDirectory = $null
    # PROPERTIES: List
    [System.Collections.Generic.List[String]] $Messages = @()
    # METHODS
    # Constructor method
    OWICModel($Model) {
        # Set properties
        $this.Name = $Model
        # Call ValidateModel to set Validates
        $this.Validates = $this.ValidateModel()
    }
    # Validate model method
    [Boolean] ValidateModel() {
        # Control variable
        [Boolean] $Return = $true
        # Determine if Model appears in JSON Models
        If ($Global:owicConfiguration.Models -Contains $this.Model) {
            # Determine that this Model appears only once in the JSON Models definition
            If (($Global:owicConfiguration.Models | Where-Object {$_.Name -eq $this.Name}).Count -eq 1) {
                # Model appears only once in the JSON Models; determine that DriversDirectory is not null
                If ([String]::IsNullOrEmpty(($Global:owicConfiguration.Models | Where-Object {$_.Name -eq $this.Name}).DriversDirectory) -eq $false) {
                    # DriversDirectory is not null or empty; populate DriversDirectory
                    $this.DriversDirectory = ($Global:owicConfiguration.Models | Where-Object {$_.Name -eq $this.Name}).DriversDirectory
                    # Determine that DriversDirectory exists
                    If((Test-Path -Path $this.DriversDirectory) -eq $false) {
                        # DriversDirectory does not exist
                        $this.Messages.Add("DriversDirectory is specified but does not exist")
                        $Return = $false
                    }
                } Else {
                    # DriversDirectory is null or empty; error
                    $this.Messages.Add("Configuration is missing DriversDirectory for this model")
                    $Return = $false
                }
            } Else {
                # Model appears more than once in JSON Models
                $this.Messages.Add("Model appears more than once in the JSON configuration file; skipping")
                $Return = $false
            }
        } Else {
            # Model does not appear in JSON models
            $this.Messages.Add("Configuration does not have a definition for this model")
            $Return = $false
        }
        # Return
        return $Return
    }
}

# MAIN
# Create a logging object
$Global:owicLogger = New-OZOLogger
# Create an object of the OWICConfiguration class
$Global:owicConfiguration = [OWICConfiguration]::new($Configuration,$NoCleanup)
# Determine if the configuration validates
If ($Global:owicConfiguration.Validates -eq $true) {
    $Global:owicLogger.Write("Configuration validates.","Information")
    # configuration validates; create an object of the OWICMain class
    [OWICMain]::new() | Out-Null
} Else {
    $Global:owicLogger.Write("Configuration did not validate.","Error")
}
