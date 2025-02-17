
# STROM.ATOM.TOOL.Common 

STROM.ATOM.TOOL.Common is a multi-purpose command-line .NET tool, containing a suite of helper functionalities designed for application development, CI/CD processes, and NuGet package management.

## Prerequisites
- .NET SDK: Ensure you have the .NET SDK installed on your machine. If not, download and install it from [the official .NET website](https://dotnet.microsoft.com/download).

## Installing the Tool
To install the tool globally on your machine, run the following command in your terminal:

Install/Update/Reinstall
```
dotnet tool install -g STROM.ATOM.TOOL.Common
```

## Use
```
satcom -h
satcom dump osversion
satcom dump envars
```

### General STROM naming conventions
---

**STROM** is a lean, modular framework built on three layers:

- **STROM**: The core architectural foundation. (**S**ystem **T**echnology **R**epository for **O**bject **M**odularization)

**Naming Conventions**
- **CELL**: The application layer. (**C**ontained **E**xecution in **L**ocalized **L**ayers)
- **ATOM**: Lightweight, single-purpose libraries. (**A**gile **T**echnology for **O**perational **M**echanics)
- **NANO**: Ultra-light libraries with only Microsoft dependencies. (**N**ucleus **A**rtifacts for **N**anoscale **O**perations)

**Targets**
- **NS**: Compatible with .NET Standard for broad compatibility (e.g., `netstandard2.1`).  
- **NETFX**: Designed for the legacy .NET Framework (e.g., `net40` for Windows XP compatibility).  
- **NET**: Built on modern, cross-platform .NET (e.g., `net7.0`).  
- **NETW**: Incorporates Windows-specific extensions (e.g., `net7.0-windows`).  
- **NETW10**: Targets Windows 10 features (e.g., `net7.0-windows10.0.19041.0`).
- **PSWH**: Powershell Core modules.
- **TOOL**: dotnet tool.
