## Appendix A. Performance results

### Appendix A.2 Workload simulation tool results

The workload simulation tool exercises the disk subsystem and server engine by simulating hundreds of concurrent client sessions.  For the medium FlashSystem C200 blueprint, the simulation was configured as follows:

#### Medium system - storage pool workload
The storage pool workload test included 10 file systems. The following command was issued:
```
perl sp_disk_load_gen.pl workload=stgpool fslist=/tsminst1/TSMfile00,/tsminst1/TSMfile01,/tsminst1/TSMfile02,/tsminst1/TSMfile03,/tsminst1/TSMfile04,/tsminst1/TSMfile05,/tsminst1/TSMfile06,/tsminst1/TSMfile07,/tsminst1/TSMfile08,/tsminst1/TSMfile09
```
These results were included in the output:
```
: Average R Throughput (KB/sec):    1144784.61
: Average W Throughput (KB/sec):    1146240.67
: Avg Combined Throughput (MB/sec): 2237.34
: Max Combined Throughput (MB/sec): 3194.28
:
: Average IOPS:                     12552.96
: Peak IOPS:                        18140.25 at 06/07/2025 10:42:56
:
: Total elapsed time (seconds):     166.60
```

#### Medium system - database workload

The database workload test included eight file systems. The following command was issued:
```
perl sp_disk_load_gen.pl workload=db
fslist=/tsminst1/TSMdbspace00,/tsminst1/TSMdbspace01,/tsminst1/TSMdbspace02,/tsminst1/TSMdbspace03,/tsminst1/TSMdbspace04,/tsminst1/TSMdbspace05,/tsminst1/TSMdbspace06,/tsminst1/TSMdbspace07
```
These results were included in the output:
```
: Average R Throughput (KB/sec):    56409.81
: Average W Throughput (KB/sec):    56329.51
: Avg Combined Throughput (MB/sec): 110.10
: Max Combined Throughput (MB/sec): 179.33
:
: Average IOPS:                     14074.41
: Peak IOPS:                        22900.23 at 06/07/2025 03:52:08
:
: Total elapsed time (seconds):     553.35
```
