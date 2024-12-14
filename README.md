# OZO Windows Installer Customizer

## Overview

This tool takes a Windows installer ISO, Answer File, Media (wallpaper, logo, icon), and Drivers; and writes a new ISO that can be used to automate Windows endpoint deployment with high consistency. It will remove undesired AppX packages.

It reads a JSON configuration file that contains *jobs*. Each job is a combination of OS, version, edition, and feature (e.g., Windows 11 Professional 22H2) and a build number that can be used to differentiate additional builds of the same os-version-edition-feature, e.g.,

- Build `000` that is Windows 11 Professional 22H2 with drivers for VMware Workstation Pro 17 virtual machines.
- Build `001` that is Windows 11 Professional 22H2 with drivers for the Dell XPS 7390.

For each combination of os-version-edition-feature, the administrator must manually generate a *catalog*, *answer file*, and list of AppX packages to remove. Once generated, these resources can be used for any number of builds.

## Recommended Directory Structure

These directories and files are referenced throughout this guide. You may substitute other locations as desired.

|Directory|Description|
|---------|-----------|
|`C:\Imaging`|Parent directory for all Imaging assets.|
|`C:\Imaging\Answer Files`|Location for storing answer files.|
|`C:\Imaging\Drivers`|Location for storing 3rd party drivers.|
|`C:\Imaging\ISO`|Location for storing Microsoft Windows installer ISOs and outputting customized ISOs.|
|`C:\Imaging\Media`|Location for storing media referenced in the configuration file.|
|`C:\Imaging\Mount`|Location for mounting WIM files.|
|`C:\Imaging\WIM`|Location for storing WIM and associated catalog file.|

## Required Resources

- Download the <a href="https://www.microsoft.com/software-download/windows11">Microsoft Windows 11 multi-edition ISO for x64 devices</a> to `C:\Imaging\ISO\`.
- Download the <a href="https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install">Windows 11 ADK</a> and install the *Deployment Tools* component. This provides the Windows SIM tool and command-line binaries (`dism.exe` and `oscdimg.exe`) used by this process.
- Download desired 3rd party drivers:
  - <a href="https://www.dell.com/support/kbdoc/en-us/000124139/dell-command-deploy-driver-packs-for-enterprise-client-os-deployment">Dell Driver Packs</a>
  - <a href="https://support.lenovo.com/us/en/">Lenovo Drivers</a>
  - <a href="https://kb.vmware.com/s/article/2032184">VMware Drivers</a>
- Extract the drivers to unique folders under `C:\Imaging\Drivers\` e.g., extract the Dell XPS 7390 driver pack to `C:\Imaging\Drivers\Dell-XPS-7390` and the VMware VM drivers to `C:\Imaging\Drivers\VMware-17-VM\`.

## Manual Steps

These steps must be performed once for each desired combination of os-version-edition-feature. Once generated, these resources can be re-used for any number of builds.

### Create an Answer File

- Double-click to mount the downloaded ISO.
- Copy `sources\install.wim` to `C:\Imaging\WIM\22H2\`.
- Eject (unmount) the ISO.
- Open *Windows SIM* as *Administrator*.
- `File > Select Windows Image > C:\Imaging\WIM\22H2\install.wim`.
- Choose your edition e.g., *Windows 11 Pro*.
- Click Yes to create a catalog.
- `File > New Answer File` and save it as `C:\Imaging\Answer Files\Windows-11-Pro-22H2-Autounattend.xml`
- Populate your answer file as desired. This is a complicated topic that is not encapsulated in these steps. For guidance, see <a href="https://onezeroone.dev/common-elements-for-windows-answer-files">this One Zero One example</a> and <a href="https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs?view=windows-11">Microsoft's instructions</a>. Note: This tool requires the following locations for logo, icon, and wallpaper media:
  - `%windir%\system32\OEM\logo.png`
  - `%windir%\system32\OEM\icon.png`
  - `%windir%\system32\OEM\wallpaper.png`
- Save and close the answer file, windows image, and Windows SIM.

### Enumerate AppX Packages

- Open an *Administrator* PowerShell and use *Dism* to determine the index number of your intended edition:

  ```
  Dism.exe /Get-WimInfo /WimFile:C:\Imaging\WIM\22H2\install.wim

  <snip>

  Index : 6
  Name : Windows 11 Pro
  Description : Windows 11 Pro
  Size : 16,479,089,353 bytes

  <snip>
  ```
- Use this *Index* number to mount the WIM:

  `Dism /Mount-Image /ImageFile:"C:\Imaging\WIM\22H2\install.wim" /Index:6  /MountDir:"C:\Imaging\Mount"`

- Enumerate the AppX Packages and make a list of packages to remove:

  `(Get-AppxProvisionedPackage -Path C:\Imaging\Mount\).DisplayName`

- Unmount the WIM:

  `Dism /Unmount-Image /MountDir:"C:\Imaging\Mount" /Discard`

## Configuration File

The configuration file is JSON so backslashes in paths must be escaped e.g., `C:\\Windows` instead of `C:\Windows`. Use the included `example-configuration.json` as a starting point. It contains two major sections: `paths` and `jobs`.

### Paths

This section describes the default paths used to find the required file assets.

|Item|Example Value|Description|
|----|-------------|-----------|
|`answerDir`|`C:\\Imaging\\Answer Files`|Default location for answer files.|
|`driversDir`|`C:\\Imaging\\Drivers`|Default location for drivers.|
|`isoDir`|`C:\\Imaging\\ISO`|Default location for ISO files.|
|`mediaDir`|`C:\\Imaging\\Media`|Default location for media.|
|`tempDir`|`C:\\Imaging\\Temp`|Default location for processing jobs. This path may not contain spaces due to a limitation with `oscdimg.exe`.|
|`oscdimgPath`|`C:\\Program Files (x86)\\Windows Kits\\10\\Assessment and Deployment Kit\\Deployment Tools\\amd64\\Oscdimg\\oscdimg.exe`|Default path to `oscdimg.exe`|
|`powerShellDismPath`|`C:\\Program Files (x86)\\Windows Kits\\10\\Assessment and Deployment Kit\\Deployment Tools\\amd64\\DISM\\Microsoft.Dism.Powershell.dll`|Default path to the PowerShell Dism module.|

### Jobs

The `jobs` section contains one or more *jobs* to be processed when the tool is run.

|Item|Required|Example Value|Description|
|----|--------|-------------|-----------|
|`jobName`|Yes|`Microsoft Windows 11 Pro 22H2`|Any unique name to identify this job.|
|`enabled`|Yes|`TRUE`|Values are `TRUE` and `FALSE`. Only enabled jobs will be processed.|
|`osName`|Yes|`Windows`|OS name (probably always Windows).|
|`version`|Yes|`11`|Major OS version. Valid values are `10`, `11`, ...`12`?|
|`edition`|Yes|`Pro`|OS edition as enumerated by *Dism*. Valid values are Home, Home N, Home Single Language, Education, Education N, Pro, Pro N, Pro Education, Pro Education N, Pro for Workstations, Pro N for Workstations.*|
|`feature`|Yes|`22H2`|Feature version. As of this writing, `22H2` is the most recent.|
|`build`|Yes|`000`|An administratively-defined build number that can be used to create additional builds of the same combination of os-version-edition-feature that differ only by e.g., included media or drivers.|
|`answerFile`|Yes|`22H2\\Windows-11-Pro-22H2-Autounattend.xml`|The path to the answer file. This may be an absolute path. If this is a relative path, the tool will look for this file under `answerDir`.|
|`inputIsoFile`|Yes|`Win11_22H2_English_x64v1.iso`|The source ISO file. This may be an absolute path. If this is a relative path, the tool will look for this file under `isoDir`.|
|`logoFile`|No|`OZO-logo.png`|The logo file. This may be an absolute path. If this is a relative path, the tool will look for this file under `mediaDir`. This file will copied into the ISO as `%windir%\system32\OEM\logo.png` so please ensure the answer file contains this value.|
|`iconFile`|No|`OZO-icon.png`|The icon file. This may be an absolute path. If this is a relative path, the tool will look for this file under `mediaDir`. This file will be copied into the ISO as `%windir%\system32\OEM\icon.png` so please ensure the answer file contains this value.|
|`wallpaperFile`|No|`OZO-wallpaper.png`|The wallpaper file. This may be an absolute path. If this is a relative path, the tool will look for this file under `mediaDir`. This file will be copied into the ISO as `%windir%\system32\OEM\wallpaper.png` so please ensure the answer file contains this value.|
|`models`|No|`["VMware-17-VM","Dell-XPS-7390"]`|A list of models that should be included in this build.|
|`removeAppxProvisionedPackages`|No|`["Microsoft.BingNews","Microsoft.BingWeather"]`|A list of AppxProvisioned packages that should be removed from the ISO.|

\* The downloadable *Microsoft Windows 11 multi-edition ISO for x64 devices* does not include the *Enterprise* or *Enterprise N* editions, however, these are also valid values if you have obtained an Enterprise ISO from the Microsoft VLC.

## Automated Build

For an idea of what this tool does, please see <a href="https://onezeroone.dev/customizing-the-windows-installer-media/">Customizing the Windows Installer Media</a>. Once the configuration file is populated, open an *Administrator* PowerShell and run the tool. Usage:

`PS> .\path\to\ozo-windows-installer-customizer.ps1 -Conf "path\to\configuration.json"`

If `-Conf` is omitted, the tool will look for `configuration.json` in the directory where it is stored.

## Failure Cases

The tool will fail under the following conditions:

- `7000`: The configuration file has JSON sytax errors.
- `7001`: The configuration file is not found or cannot be read.
- `7002`: Cannot find `oscdimg.exe`.
- `7003`: Cannot find `dism.exe`.
- `7004`: The required PowerShell module is not found.
- `7005`: No jobs are specified.
- `7006`: A job is missing a required element (or the specified file cannot be found).
- `7007`: The temporary directory cannot be created.
- `7008`: One or more specified models are not found.
- `7009`: The output ISO file already exists.
- `7010`: The temporary directory path contains spaces (this path cannot contain spaces due to a limitation with `oscdimg.exe`).
- `7011`: The temporary directory already exists.
- `7012`: The temporary directory disk is not a fixed disk.
- `7013`: The temporary directory disk has less than 4 x the size of the source ISO available.

## Credits

The <a href="https://www.pexels.com/photo/abstract-wallpaper-13884938">custom wallpaper image</a> included in this repository is by Marcin Jozwiak and was obtained from <a href="https://www.pexels.com">Pexels</a> where it is licensed for use under the <a href="https://www.pexels.com/license">Pexels License</a>.

The One Zero One logo and icon use the highly accessible and inclusive *<a href="https://en.wikipedia.org/wiki/Atkinson_Hyperlegible">Atkinson Hyperlegible</a>* font which can be downloaded from <a href="https://brailleinstitute.org/freefont">The Braille Institute</a> and whose importance is excellently described in <a href="https://www.youtube.com/watch?v=wjE5eHLICzc">a youtube video by Linus Bowman</a>.
