# OZO Windows Installer Customizer Usage Guide
## Overview
Customizes the Windows installer ISO based on a JSON configuration file containing parameters for OS, version, edition, and features. It enables automation with an Answer File, can include custom media (wallpapers, logos, etc.), and can remove undesired AppX packages.

_Note: For guidance on installing this script, please see [**README.md**](readme.md)._

This script reads a JSON configuration file containing one or more _Jobs_. Each job is a combination of OS, version, edition, and feature (e.g., Windows 11 Professional 22H2) and a user-defined _build_ number that differentiates builds of the same os-version-edition-feature, e.g.,

- Build `000` is Windows 11 Professional 22H2 with drivers for VMware Workstation Pro 17 virtual machines.
- Build `001` is Windows 11 Professional 22H2 with drivers for the Dell XPS 7390.

For each new Windows release (e.g., Windows 11 Pro 22H2, Windows 11 Pro 24H2, etc.), the administrator must manually generate a *catalog*, *answer file*, and list of AppX packages to remove. Once generated, these resources can be used for any number of automated builds.

## Table of Contents

* [Overview](#overview)
* [Prerequisites](#prerequisites)
* [Configure Jobs](#configure-jobs)
* [Run the Automated Build](#run-the-automated-build)

## Prerequisites
### Create an _Imaging_ Directory Structure

These directories and files are referenced throughout this guide. You may substitute other locations as desired but please note that due to a limitation with `oscdimg.exe`, your paths may not contain spaces.

|Directory|Description|
|---------|-----------|
|`C:\Imaging\Answer Files`|Answer files.|
|`C:\Imaging\Cofniguration`|JSON configuration file(s).|
|`C:\Imaging\Drivers`|Third-party drivers.|
|`C:\Imaging\ISO`|Source and target ISOs.|
|`C:\Imaging\Media`|Custom media (logos, icons, and wallpapers).|
|`C:\Imaging\Mount`|Mount point for WIM files.|
|`C:\Imaging\Temp`|Temporary files.|
|`C:\Imaging\WIM`|WIMs and their associated catalog files.|

You can use this PowerShell command to create the recommended directory structure:
```powershell
ForEach ($Item in @("Answer Files","Drivers","ISO","Media","Mount","Temp","WIM")) { New-Item -Force -ItemType Directory -Path (Join-Path -Path $Env:SystemDrive -ChildPath (Join-Path -Path "Imaging" -ChildPath $Item)) }
```

### Obtain the Microsoft ADK, Windows 11 ISO, and Driver Packs

* Download and install the [Windows 11 ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install). Select the _Deployment Tools_ component during installation; this provides the Windows SIM tool, the DISM PowerShell module, and the command-line `oscdimg.exe` binary.
* Download the [Microsoft Windows 11 multi-edition ISO for x64 devices](https://www.microsoft.com/software-download/windows11) to `C:\Imaging\ISO\`.
* Download desired 3rd party drivers, e.g.,:
    * [Dell Driver Packs](https://www.dell.com/support/kbdoc/en-us/000124139/dell-command-deploy-driver-packs-for-enterprise-client-os-deployment)
    * [Lenovo Drivers](https://support.lenovo.com/us/en/)
    * [VMWare Drivers](https://kb.vmware.com/s/article/2032184)
* Extract the drivers to unique folders under `C:\Imaging\Drivers\` e.g., extract the Dell XPS 7390 driver pack to `C:\Imaging\Drivers\Dell-XPS-7390` and the VMware VM drivers to `C:\Imaging\Drivers\VMware-17-VM\`.

### Create an Answer File and Enumerate AppxPackages
For each new combination of OS, version, edition, and feature (e.g., Windows 11 Pro 22H2) you must manually generate an _Answer File_ and enumerate the included _AppxPackages_. Once generated, these resources can be re-used for any number of _builds_ of the same os-version-edition-feature.

#### Answer File

* In `C:\Imaging\ISO`, double-click to mount the ISO downloaded from Microsoft to the `D` drive. 
* Copy `D:\sources\install.wim` to `C:\Imaging\WIM\22H2\`.
* Right-click and _Eject_ the ISO.
* Open _Windows SIM_ as _Administrator_
* `File > Select Windows Image > C:\Imaging\WIM\22H2\install.wim`.
* Choose your edition e.g., _Windows 11 Pro_.
* Click Yes to create a catalog.
* `File > New Answer File` and save it as `C:\Imaging\Answer Files\Windows-11-Pro-22H2-Autounattend.xml`
* Populate your answer file as desired. This is a complicated topic that is not encapsulated in these steps. For guidance, see [this One Zero One example](https://onezeroone.dev/common-elements-for-windows-answer-files) and [Microsoft's instructions](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs?view=windows-11). Note: If you choose to include custom media (logo, icon, and wallpaper), specify these locations in your answer file:
    * `%windir%\system32\OEM\logo.png`
    * `%windir%\system32\OEM\icon.png`
    * `%windir%\system32\OEM\wallpaper.png`
* Save and close the answer file, windows image, and Windows SIM.

#### AppX Packages

* Open an _Administrator_ PowerShell and use `Get-WindowsImage` to obtain the _Index_ number of your desired edition:
    ```powershell
    Get-WindowsImage -ImagePath "C:\Imaging\WIM\22H2\install.wim"

    <snip>

    Index : 6
    Name : Windows 11 Pro
    Description : Windows 11 Pro
    Size : 16,479,089,353 bytes

    <snip>
    ```
* Use this *Index* number to mount the desired image:
    ```powershell
    Mount-WindowsImage -Path "C:\Imaging\Mount" -ImagePath "C:\Imaging\WIM\22H2\install.wim" -Index 6
    ```
* Enumerate the AppX Packages and make a note of any packages you would like to remove from the image (these will be listed in the JSON configuration file later):

    ```powershell
    (Get-AppxProvisionedPackage -Path "C:\Imaging\Mount").DisplayName
    ```
* Dismount the WIM:
    ```powershell
    Dismount-WindowsImage -Path "C:\Imaging\Mount" -Discard
    ```

## Configure Jobs
Save [`example-configuration.json`](example-configuration.json) as `C:\Imaging\Configuration\ozo-windows-installer-customizer.json` as a starting point. It contains a dictionary with three definitions: `Paths`, `Models`, and `Jobs`:

```json
{
    "Paths":{
        "TempDir":"",
        "OscdimgPath":""
    },
    "Models":[
        {
            "Name":"",
            "DriversDirectory":""
        }
    ],
    "Jobs":[
        {
            "Enabled":,
            "Name":"",
            "OSName":"",
            "Version":"",
            "Edition":"",
            "Feature":"",
            "Build":"",
            "Files":{
                "answerPath":"",
                "sourceISOPath":"",
                "logoPath":"",
                "iconPath":"",
                "wallpaperPath":""
            },
            "Models":[],
            "removeAppxProvisionedPackages":[]
        }
    ]
}

```

### Paths

Paths is a _dictionary_ containing definitions for `TempDir` and `OscdImgPath`. Please note that backslashes must be escaped e.g., `C:\\Windows` instead of `C:\Windows`.

|Item|Example Value|Description|
|----|-------------|-----------|
|`TempDir`|`C:\\Imaging\\Temp`|Temporary location for processing jobs.|
|`OscdimgPath`|`C:\\Program Files (x86)\\Windows Kits\\10\\Assessment and Deployment Kit\\Deployment Tools\\amd64\\Oscdimg\\oscdimg.exe`|Path to `oscdimg.exe`.|

### Models
Models is a _list_. Each list item is a _dictionary_ containing a _Name_ and _DriversDirectory_ for a given driver pack.

|Item|Example Value|Description|
|----|-------------|-----------|
|`Name`|`Dell-XPS-7390`|A user-defined name for this driver pack. This can be any string. This _Name_ may be referenced in any number of _Jobs_.|
|`DriversPath`|`C:\\Imaging\\Drivers\\Dell-XPS-7390`|The path to the expanded driver pack for this _Name_.|

### Jobs
Jobs is a _list_. Each list item is a _dictionary_ containing the details for a given job. The configuration file must contain at least one job, and may contain as many jobs as desired.

|Item|Required|Example Value|Description|
|----|--------|-------------|-----------|
|`Enabled`|Yes|`true`|Controls whether or not this job is processed when the script runs. This allows you to maintain one configuration file containing all jobs and only process the desired jobs on each run. Valid values are `true` and `false` (Note: Do not use quotes).|
|`Name`|Yes|`Microsoft Windows 11 Pro 22H2`|A user-defined name that uniquely identifies this job.|
|`OSName`|Yes|`Windows`|OS name (probably always Windows).|
|`Version`|Yes|`11`|Major OS version. Valid values are `10`, `11`, ...`12`?|
|`Edition`|Yes|`Pro`|OS edition as enumerated by *Dism*. Valid values are Home, Home N, Home Single Language, Education, Education N, Pro, Pro N, Pro Education, Pro Education N, Pro for Workstations, Pro N for Workstations.*|
|`Feature`|Yes|`22H2`|Feature.|
|`Build`|Yes|`000`|An user-defined build number differentiates builds of the same OS, version, edition, and feature that can differ by included media or drivers.|
|`Files`|Yes|See `Jobs.Files` (below)|This definition is a dictionary containing the paths to job files.|
|`Models`|No|`["VMware-17-VM","Dell-XPS-7390"]`|A list of models that should be included in this build.|
|`removeAppxProvisionedPackages`|No|`["Microsoft.BingNews","Microsoft.BingWeather"]`|A list of AppxProvisioned packages that should be removed from the ISO.|

\* The downloadable *Microsoft Windows 11 multi-edition ISO for x64 devices* does not include the *Enterprise* or *Enterprise N* editions, however, these are also valid values if you have obtained an Enterprise ISO from the Microsoft VLC.

### Jobs.Files
Jobs.Files is a dictionary containing paths to the answer file, source ISO, and [optional\] logo, icon, and wallpaper files.

|Item|Required|Example value|Description|
|----|--------|-------------|-----------|
|`answerPath`|Yes|`C:\\Imaging\\Answer Files\\22H2\\Windows-11-Pro-22H2-Autounattend.xml`|The path to the answer file. This may be an absolute path. If this is a relative path, the tool will look for this file under `answerDir`.|
|`sourceIsoPath`|Yes|`C:\\Imaging\\ISO\\Win11_22H2_English_x64v1.iso`|The source ISO file. This may be an absolute path. If this is a relative path, the tool will look for this file under `isoDir`.|
|`logoFile`|No|`C:\\Imaging\\Media\\OZO-logo.jpg`|The logo file. This may be an absolute path. If this is a relative path, the tool will look for this file under `mediaDir`. This file will copied into the ISO as `%windir%\system32\OEM\logo.png` so please ensure the answer file contains this value.|
|`iconFile`|No|`C:\\Imaging\\Media\\OZO-icon.png`|The icon file. This may be an absolute path. If this is a relative path, the tool will look for this file under `mediaDir`. This file will be copied into the ISO as `%windir%\system32\OEM\icon.png` so please ensure the answer file contains this value.|
|`wallpaperFile`|No|`C:\\Imaging\\Media\\OZO-wallpaper-1900x1200.png`|The wallpaper file. This may be an absolute path. If this is a relative path, the tool will look for this file under `mediaDir`. This file will be copied into the ISO as `%windir%\system32\OEM\wallpaper.png` so please ensure the answer file contains this value.|

## Run the Automated Build

For an idea of the steps performed by this script, please see [Customizing the Windows Installer Media](https://onezeroone.dev/customizing-the-windows-installer-media). Once the configuration file is populated, open an _Administrator_ PowerShell and run the tool. Usage:

```powershell
ozo-windows-installer-customizer -Configuration "C:\Imaging\Configuration\ozo-windows-installer-customizer.json"
```

