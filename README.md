# Interface live statistics tracker utility - for Linux x86-64 systems

This simple command line utility can be used to show per second simple live statistics for a given network interface, whose name is specified as its only parameter. It tracks state, total transmitted and received data and current transmit and receive bandwidth usage. It also maintains a live database with the same data for integration with other appliances. See below.

### Usage

```> iftrack interface```

Where interface is the interface name. One can run 'iftrack' without parameters to see a list of currently available interfaces that can be tracked.

### Install

Just copy the binary 'iftrack' file to your preferred binary location (e.g., '/usr/bin', for system-wide, or '~/.local/bin' for user restricted availability), and run it as specified above.

### Uninstall

Just remove the binary from the location you've copied previously. That's it. ;)

### Script support for gathered data

This application, when running, creates and updates a tmpFS entry for the specified interface, with all processed data formatted for exhibition. So, one can run it (as a service or not), for example: 'iftrack eth0 2>/dev/null', so it maintains an entry with data from 'eth0' interface at '/tmp/iftrack/eth0' folder.
Those files can be read by a script, or an application, and reused by them, for example, as data for dwm-like window managers status bar about that interface. Data is already formatted exactly as shown by 'iftrack' application itself.

### Compiling from source

The following are needed to compile this from source:

 - [fasm2](https://github.com/tgrysztar/fasm2 "flat assembler 2") assembler;
 - [fastcall](https://github.com/Jesse-6/fastcall "C style fastcall macro toolkit - for fasm2 assember") macro kit;
 - LLD linker (optional): for smaller, less bloated executables.
 
Once one got the above properly set up, the 'build.sh' script at fastcall macro can be used to build this binary as fine as possible, by running:

```
> build.sh iftrack
> mv iftrack ../
```




