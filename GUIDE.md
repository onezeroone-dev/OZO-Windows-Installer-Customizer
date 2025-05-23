# OZO Windows Installer Customizer Usage Guide
## Overview
Customizes the Windows installer ISO. It enables automation with an Answer File, can include custom media (wallpapers, logos, etc.), and can remove undesired AppX packages.

_Note: For guidance on installing this script, please see [**README.md**](README.md)._

This script reads a JSON configuration file containing one or more _Jobs_. Each job is a combination of OS, version, edition, and feature (e.g., Windows 11 Pro 24H2) and a user-defined _build_ number that differentiates builds of the same combination, e.g.,

* Windows 11 Pro 24H2 _with drivers for the Dell XPS 15 9530_ is build `000`.
* Windows 11 Pro 24H2 _with drivers for VMWare 17 virtual machines_ is build `001`.

For each new Windows combination (e.g., Windows 11 Pro 22H2, Windows 11 Home 24H2, etc.), you must prepare a _catalog_, an _answer file_, a list of AppX packages to remove, and [optionally\] a set of logo, icon, and wallpaper image files. Once generated, these resources can be used for any number of builds of the same combination.

## Table of Contents

* [Overview](#overview)
* [Prerequisites](#prerequisites)
* [Configure Jobs](#configure-jobs)
* [Run the Automated Build](#run-the-automated-build)

## Prerequisites
### Create an _Imaging_ Directory Structure

These recommended directories are referenced throughout this guide. You may substitute other paths as desired, but please note that the _ISO_ directory path may not contain spaces.

|Directory|Description|
|---------|-----------|
|`C:\Imaging\Answer Files`|Answer files.|
|`C:\Imaging\Configuration`|JSON configuration file(s).|
|`C:\Imaging\Drivers`|Third-party drivers.|
|`C:\Imaging\ISO`|Source and target ISOs. Due to a limitation with `oscdimg.exe`, this path may not contain spaces.|
|`C:\Imaging\Media`|Custom media (logos, icons, and wallpapers).|
|`C:\Imaging\Mount`|Location for temporarily mounting WIM files.|
|`C:\Imaging\Temp`|Temporary files.|
|`C:\Imaging\WIM`|WIMs and their associated catalog files.|

You can use this PowerShell command to create the recommended directory structure:
```powershell
ForEach ($Item in @("Answer Files","Drivers","ISO","Media","Mount","Temp","WIM")) { New-Item -Force -ItemType Directory -Path (Join-Path -Path $Env:SystemDrive -ChildPath (Join-Path -Path "Imaging" -ChildPath $Item)) }
```

### Obtain the Microsoft ADK, Windows 11 ISO, and Driver Packs

* Download and run the [Windows 11 ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) as _Administrator_. Select the _Deployment Tools_ component during installation; this provides the Windows SIM tool, the DISM PowerShell module, and the command-line `oscdimg.exe` binary.
* Download the [Microsoft Windows 11 multi-edition ISO for x64 devices](https://www.microsoft.com/software-download/windows11) to `C:\Imaging\ISO\`.
* Download desired 3rd party drivers, e.g.,:
    * [Dell Driver Packs](https://www.dell.com/support/kbdoc/en-us/000124139/dell-command-deploy-driver-packs-for-enterprise-client-os-deployment)
    * [Lenovo Drivers](https://support.lenovo.com/us/en/)
    * [VMWare Drivers](https://kb.vmware.com/s/article/2032184)
* Extract the drivers to unique folders under `C:\Imaging\Drivers\` e.g., extract the Dell XPS 9530 driver pack to `C:\Imaging\Drivers\Dell-XPS-15-9530` and the VMware 17 drivers to `C:\Imaging\Drivers\VMware-17`.

### Create a Catalog and Answer File; and Enumerate AppxPackages
For each new combination (e.g., Windows 11 Pro 24H2) you must manually generate an _Answer File_ and enumerate the included _AppxPackages_. Once generated, these resources can be re-used for any number of _builds_ of the same combination.

#### Catalog and Answer File

* Double-click the Windows 11 24H2 multi-edition ISO in `C:\Imaging\ISO` to mount it to the `D` drive. 
* Copy `D:\sources\install.wim` to `C:\Imaging\WIM\24H2\`.
* Right-click the `D` drive and _Eject_ the ISO.
* _Start > Windows Kits_ and open _Windows System Image Manager_ as _Administrator_.
* _File > Select Windows Image > `C:\Imaging\WIM\24H2\install.wim`_.
* Choose your edition e.g., _Windows 11 Pro_.
* Click _Yes_ to create a catalog.
* _File > New Answer File_ and save it as `C:\Imaging\Answer Files\Windows-11-Pro-24H2-000-Autounattend.xml`.
* Populate your answer file according to your needs. This is a complicated topic that is not articulated here. For guidance, see [this One Zero One example](https://onezeroone.dev/common-elements-for-windows-answer-files) and [Microsoft's instructions](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs?view=windows-11).
* Save and close the answer file, windows image, and Windows System Image Manager.

#### AppX Packages

* Open an _Administrator_ PowerShell and use `Get-WindowsImage` to obtain the _Index_ number of your desired edition:
    ```powershell
    Get-WindowsImage -ImagePath "C:\Imaging\WIM\24H2\install.wim"

    <snip>

    Index : 6
    Name : Windows 11 Pro
    Description : Windows 11 Pro
    Size : 16,479,089,353 bytes

    <snip>
    ```
* Use this *Index* number to mount the desired image:
    ```powershell
    Mount-WindowsImage -Path "C:\Imaging\Mount" -ImagePath "C:\Imaging\WIM\24H2\install.wim" -Index 6
    ```
* Enumerate the AppX Packages and make a note of any packages you would like to remove from the image. These will be listed in the JSON configuration file in _Configure Jobs_ (below):

    ```powershell
    (Get-AppxProvisionedPackage -Path "C:\Imaging\Mount").DisplayName
    ```
* Dismount the WIM:
    ```powershell
    Dismount-WindowsImage -Path "C:\Imaging\Mount" -Discard
    ```

## Configure Jobs
Save [`example-configuration.json`](example-configuration.json) as `C:\Imaging\Configuration\ozo-windows-installer-customizer.json` as a starting point. It contains a dictionary with two definitions: `Paths` and `Jobs`. The schema is as follows:

```json
{
    "Paths":{
        "TempDir":"",
        "OscdimgPath":""
    },
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
            "Drivers":[],
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

### Jobs
Jobs is a _list_. Each list item is a _dictionary_ containing the details for a given job. The configuration file must contain at least one job, and may contain as many jobs as desired.

|Item|Required|Example Value|Description|
|----|--------|-------------|-----------|
|`Enabled`|Yes|`true`|Controls whether or not this job is processed when the script runs. This allows you to maintain one configuration file containing all jobs and only process the desired jobs on each run. Allowed values are `true` and `false` (Note: Do not use quotes).|
|`Name`|Yes|`Microsoft Windows 11 Pro 24H2 Build 000 for the Dell XPS 15 9530`|A user-defined name that uniquely identifies this job.|
|`OSName`|Yes|`Windows`|OS name. Values will generally be `Windows` or `Windows Server`.|
|`Version`|Yes|`11`|Major OS version. Allowed values are `10`, `11`, ...`12`?|
|`Edition`|Yes|`Pro`|OS edition as enumerated by *Dism* such as Home, Education, Pro, and Enterprise. *|
|`Feature`|Yes|`24H2`|Feature.|
|`Build`|Yes|`000`|An user-defined build number that differentiates builds of the same OS, version, edition, and feature. Builds should have a corresponding answer file and may differ by included media or drivers.|
|`Files`|Yes|See `Jobs.Files` (below)|This definition is a dictionary containing the paths to job files.|
|`Drivers`|No|`["C:\\Imaging\\Drivers\\VMware-17","C:\\Imaging\\Drivers\\Dell-XPS-15-9530"]`|A list of directories containing drivers that should be included in this build.|
|`removeAppxProvisionedPackages`|No|`["Microsoft.BingNews","Microsoft.BingWeather"]`|A list of AppxProvisioned packages that should be removed from the build.|

\* The downloadable *Microsoft Windows 11 multi-edition ISO for x64 devices* does not include the _Enterprise_ editions, however, these are also valid values if you have obtained an Enterprise ISO from Microsoft VLC. Likewise, the Windows Server editions are also valid if you are customizing a server ISO.

### Jobs.Files
`Jobs.Files` is a dictionary containing paths to the answer file, source ISO, and [optional\] logo, icon, and wallpaper files.

|Item|Required|Example value|Description|
|----|--------|-------------|-----------|
|`answerPath`|Yes|`C:\\Imaging\\Answer Files\\Windows-11-Pro-24H2-000-Autounattend.xml`|The path to the answer file. This example is named for the os-version-edition-feature-build.|
|`sourceIsoPath`|Yes|`C:\\Imaging\\ISO\\Win11_24H2_English_x64.iso`|The source ISO file.|
|`logoFile`|No|`C:\\Imaging\\Media\\OZO-logo.jpg`|The logo file. This file will copied into the ISO as the file name specified in the Autounattend XML.|
|`iconFile`|No|`C:\\Imaging\\Media\\OZO-icon.png`|The icon file. This file will be copied into the ISO as the file name specified in the Autounattend XML.|
|`wallpaperFile`|No|`C:\\Imaging\\Media\\OZO-wallpaper-1900x1200.png`|The wallpaper file. This file will be copied into the ISO as the file name specified in the Autounattend XML.|

## Run the Automated Build

For an idea of the steps performed by this script, please see [Customizing the Windows Installer Media](https://onezeroone.dev/customizing-the-windows-installer-media). Once the configuration file is populated, open an _Administrator_ PowerShell and run the tool. Usage:

```powershell
ozo-windows-installer-customizer -Configuration "C:\Imaging\Configuration\ozo-windows-installer-customizer.json"
```
