# Fakeload for IBM Storage Protect

## What is fakeload?

**Fakeload** uses the Client API of IBM Storage Protect to `backup` and `restores` RAM buffers to the IBM Storage Protect server. This unique ability to backup buffers from RAM allows `fakeload` to send (and receive) data without disk IOPS bottlenecks.  You can transfer data to to IBM Storage Protect server - at very high speeds, thereby simulating a theoretical maximum (in the lab or on-the-field).

## Where to find fakeload tools?

**Fakeload** binaries are located under `tools/bin/<OS>` folder.


## Usage

Type `fakeload` without any arguments - for the syntax and options available:

```
(C) Copyright IBM Corporation 2001, 2009.  All Rights Reserved.
This is an unsupported IBM tool.  No warranty expressed or implied.
Fakeload version 2.13
Usage:
  fakeload sel|res|arc|ret|inc obj_size num_of_obj [nodename] [options]
Options:
  [-r|-R|-z|-f filename] Fill buffer with random, zeros, or data from a file,
     zero filled buffer is default.  Used to alter compression ratio of data.
     -R randomizes every buffer sent, not just the first buffer.
  [-b bufsize] size of buffer to give to IBM Storage Protect API, 1MB is default
  [-g txngroupmax] number of obj to pass before end txn, should be <= server
     setting, 256 default
  [-l txnbytelim] amt of data to pass before end txn, should be <= client
     setting, 2000MB default
  [-s name] filespace name to use, default is something descriptive
     like /1024MB_of_10KB
  [-h name] hl (directory) name to place/get files from
  [-S] sparse restore.  Only restores every other file. (For tape testing.)
  [-q restorefilespec] ll query string to pass to server for restore/retrieve
  [-Q restorefilespec] hl query string to pass to server for restore/retrieve
  [-m mgmtclass] specify management class to use.  Otherwise uses default
     management class.
  [-n filename] specify file name prefix to send, default is 'file'
  [-N file_number] specify file number to start with
  [-o offset] specify buffer offset for unique data
  [-p passwd] specify node password
  [-pd pctDuplicate] specify percentage of duplicate data buffers
  [-P percent ] percentage of changed files for incremental backup.  Default 10 percent.
  [-d descrip] archive description.  Optionally used for archive and retrieve.
  [-a] Abort all transactions for data sent.
  [-O offset length ] do partial object retrieve
  [-t option_string ] specify options to IBM Storage Protect.
  [-C] Simulate a CM8 like workload.
  [-c] use IBM Storage Protect API supplied buffers to avoid memory copy.
  [-e key] Specify an encryption key.
  [-G groupName] used for creating all files in a group only for backup.
  [-u numSubGroups] create numSubGroups of sub groups only for backup.

  Sizes may be expressed using postfixes, i.e. 10M is equivalent to
     104865760 bytes

  The keyword 'forever' may be used for num_of_obj to run continuously

  An "inc"remental backup must be preceded by running
  a "sel"ective with the same parameters.
```

### Backup Example

Example: Backup 100 1 megabyte files using the nodename verdin you would run:

```
root@verdin["/home/dsm"]
%fakeload sel 1m 100 verdin -p passwd
(C) Copyright IBM Corporation 2001, 2007.  All Rights Reserved.
This is an unsupported IBM tool.  No warranty expressed or implied.
<000.000> Fakeload version 2.03
<000.000> Compiled with version 5.4.0.0 API.
<000.000> Using version 6.1.0 API library.
<000.000> Object size is 1MB
<000.000> Total data: 100MB, 100 objects
<000.000> Creating buffer of size 1048576 bytes, type=z.
<000.093> Connected to 6.1.1.0 server CIRCE
<000.093> Registering filespace /100MB_of_1MB.
<000.126> Sending data.
<000.126>   Begin Transaction
<000.925>   End Transaction
<000.990> Successful.  Throughput is 103400.3 KB/sec.
```

Note that the -p argument may or may not be necessary depending on use of the PASSWORDACCESS client settings.

The numbers on the left are seconds since fakeload was started, a running elapsed time.

### Restore Example

To retrieve that data back run:

```
root@verdin["/home/dsm"]
%fakeload res 1m 100 verdin
(C) Copyright IBM Corporation 2001, 2007.  All Rights Reserved.
This is an unsupported IBM tool.  No warranty expressed or implied.
<000.000> Fakeload version 2.03
<000.000> Compiled with version 5.4.0.0 API.
<000.000> Using version 6.1.0 API library.
<000.000> Object size is 1MB
<000.000> Total data: 100MB, 100 objects
<000.000> Creating buffer of size 1048576 bytes.
<000.087> Connected to 6.1.1.0 server CIRCE
<000.087> Running Query...
<000.087>   Searching for filespace:"/100MB_of_1MB" hl:"/" ll:"/file.*"
<000.125> End Query.
<000.125> Retrieving Data.
<001.358> Retrieved 104857600 bytes of data.
<001.359> Successful.  Throughput is 75341.3 KB/sec.
```

`Fakeload` allows number postfixes 'k', 'm' and 'g', I.e. 1m = 1048576.

---
