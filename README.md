# OZO Windows Installer Customizer Installation and Usage
## Overview
Customizes the Windows installer ISO based on a JSON configuration file containing parameters for OS, version, edition, and features. It enables automation with an Answer File, can include custom media (wallpapers, logos, etc.), and can remove undesired AppX packages.

_Note: For guidance on configuration and more detail on using this script, please see [**GUIDE.md**](GUIDE.md)._

## Prerequisites
* PowerShell version 5.1 or newer.
* The latest [Microsoft Assessment and Deployment Kit](https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install) ("ADK"). Select the _Deployment Tools_ option during installation. This provides the DISM PowerShell module and `oscdimg.exe`.
* The `DISM`, `ImportExcel`, and `OZOLogger` modules. The `DISM` module is provided by the ADK. The `ImportExcel` and `OZOLogger` moduls are published to [PowerShell Gallery](https://learn.microsoft.com/en-us/powershell/scripting/gallery/overview?view=powershell-5.1), You can also install and run the [_OZO Window Event Log Provider Setup_](https://github.com/onezeroone-dev/OZO-Windows-Event-Log-Provider-Setup/blob/main/README.md) script to support the optimal user of the `OZOLogger` module. Ensure your system is configured for this repository then execute the following in an _Administrator_ PowerShell:

    ```powershell
    Install-Script ozo-windows-event-log-provider-setup
    Install-Module ImportExcel,OZOLogger
    ozo-windows-event-log-provider-setup.ps1
    ```

## Installation
This script is published to [PowerShell Gallery](https://learn.microsoft.com/en-us/powershell/scripting/gallery/overview?view=powershell-5.1). Ensure your system is configured for this repository then execute the following in an _Administrator_ PowerShell:

```powershell
Install-Script ozo-windows-installer-customizer
```

## Usage

```
ozo-windows-installer-customizer <Parameters>
```

## Parameters
|Parameter|Description|
|---------|-----------|
|`Configuration`|The path to the JSON configuration file. Defaults to ozo-windows-installer-customizer.json in the same directory as this script. For guidance on creating a JSON configuration file, please see [**GUIDE.md**](GUIDE.md)|
|`Nocleanup`|Do not clean up the temporary file assets. Mostly used for testing and debugging.|
|`OutDir`|Output directory for the Excel report. Defaults to the current directory.|

## Logging and Reporting
This script writes general status messages to the Windows Event Log. If [_OZO Window Event Log Provider Setup_](https://github.com/onezeroone-dev/OZO-Windows-Event-Log-Provider-Setup/blob/main/README.md) has been implemented, messages are written to the _One Zero One_ provider. Otherwise, messages are written to the _Microsoft-Windows-PowerShell_ provider.

Every run of the script produces a Excel file containing details about each customization job.

## Notes
Run this script as _Administrator_. For guidance on configuration and using this script, please see [**GUIDE.md**](GUIDE.md).

## Acknowledgements
Special thanks to my employer, [Sonic Healthcare USA](https://sonichealthcareusa.com), who has supported the growth of my PowerShell skillset and enabled me to contribute portions of my work product to the PowerShell community.

The [custom wallpaper image](https://www.pexels.com/photo/abstract-wallpaper-13884938) included in this repository is by Marcin Jozwiak and was obtained from [Pexels](https://www.pexels.com) where it is licensed for use under the [Pexels License](https://www.pexels.com/license).

The One Zero One logo and icon use the highly accessible and inclusive [Atkinson Hyperlegible](https://en.wikipedia.org/wiki/Atkinson_Hyperlegible) font which can be downloaded from [The Braille Institute](https://brailleinstitute.org/freefont) and whose importance is excellently described in <a href="">[this YouTube video](https://www.youtube.com/watch?v=wjE5eHLICzc) by Linus Bowman.
