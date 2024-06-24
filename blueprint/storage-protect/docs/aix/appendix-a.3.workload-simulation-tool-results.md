## Appendix A. Performance results

### Workload Simulation Tool results

Sample data from the workload simulation tool is provided for blueprint test lab systems. Both a storage pool workload and a database workload were tested on each system.

For workload simulation results on small and medium blueprint systems, see the Blueprint and Server Automated Configuration for Linux x86, Version 4 Release 4 at IBM Storage Protect Blueprints. Results that were obtained on the Linux x86 operating system are comparable to results that can be expected on an AIX system.

#### Large system - storage pool workload

The storage pool workload test included 32 file systems. The following command was issued:
```
perl sp_disk_load_gen.pl workload=stgpool fslist=/tsminst1/TSMfile00,/tsminst1/TSMfile01, ... /tsminst1/TSMfile31
```
These results were included in the output:
```
:  Average R Throughput (KB/sec):	 2347668.86
:  Average W Throughput (KB/sec):	 2371414.29
:  Avg Combined Throughput (MB/sec): 4608.48
:  Max Combined Throughput (MB/sec): 5252.03
:
:  Average IOPS:			         17760.45
:  Peak IOPS:				         20203.80 at 23:26:52
:
:  Total elapsed time (seconds):	 147
```

#### Large system - database workload

The database workload test included 12 file systems. The following command was issued:
```
perl sp_disk_load_gen.pl workload=db fslist=/tsminst1/TSMdbspace00,/tsminst1/TSMdbspace01,/tsminst1/TSMdbspace02, ... /tsminst1/TSMdbspace11
```
These results were included in the output:
```
:  Average R Throughput (KB/sec):	 210615.74
:  Average W Throughput (KB/sec):	 212108.22
:  Avg Combined Throughput (MB/sec): 412.82
:  Max Combined Throughput (MB/sec): 515.00
:
:  Average IOPS:			         51566.64
:  Peak IOPS:				         64253.80 at 23:43:33
```

#### IBM Elastic Storage System system - storage pool workload

Workload simulation results are not currently available.
