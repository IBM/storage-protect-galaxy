# storage-protect-galaxy

The repository of assets (blueprints, tools, solution, best practices, and reference implementations) related to the IBM Storage Protect and IBM Storage Protect Plus offerings.

## Table of Content

### Blueprint assets
| Assets    |        |
|-----------|--------|
| Blueprints for IBM Storage Protect (on premise) | <ul><li>[Blueprint for AIX](./storage-protect/docs/aix/Storage%20Protect%20Blueprint%20for%20AIX.md)</li><li>[Blueprint for Linux](./storage-protect/docs/linux/Storage%20Protect%20Blueprint%20for%20Linux.md)</li><li>[Blueprint for Linux on Power Systems](./storage-protect/docs/ppc-linux/Storage%20Protect%20Blueprint%20for%20Linux%20on%20Power%20Systems.md)</li><li>[Blueprint for Windows](./storage-protect/docs/windows/Storage%20Protect%20Blueprint%20for%20Windows.md) </li></ul> |
| Blueprints for IBM Storage Protect (on Cloud) | <ul><li> [Cloud Blueprint for AWS](./storage-protect/docs/cloud/aws/Storage%20Protect%20Blueprint%20for%20Amazon%20Web%20Services.md)</li><li>[Cloud Blueprint for Azure](./storage-protect/docs/cloud/azure/Storage%20Protect%20Blueprint%20for%20Azure.md)</li><li>[Cloud Blueprint for Google Cloud](./storage-protect/docs/cloud/google/Storage%20Protect%20Blueprint%20for%20Google%20Cloud.md)</li><li>[Cloud Blueprint for IBM Cloud](./storage-protect/docs/cloud/ibm-cloud/Storage%20Protect%20Blueprint%20for%20IBM%20Cloud.md)</li></ul>|
| Blueprint for IBM Storage Protect for Enterprise Resource Planning | <ul><li>[Blueprint for SAP HANA](./storage-protect/docs/sap-hana/Storage%20Protect%20Blueprint%20for%20SAP%20HANA.md)</li></ul> |
| Blueprints for IBM Storage Protect Plus | <ul><li> [Blueprint for IBM Storage Protect Plus](./storage-protect-plus/docs/Spectrum%20Protect%20Plus%20Blueprint.md) </li></ul> |

### Solution assets
| Assets    |        |
|-----------|--------|
| Cyber Resiliency Solution for IBM Storage Scale (using IBM Storage Protect) | <ul><li>[Cyber Resiliency Solution for IBM Storage Scale](./solutions/cyber-resiliency-solution-for-storage-scale/Cyber%20Resiliency%20Solution%20for%20IBM%20Storage%20Scale.md)</li></ul> |
| Petascale Data Protection Solution | <ul><li>[Petascale Data Protection Solution](./solutions/petascale-data-protection/Petascale%20Data%20Protection.md)</li></ul> |

### Best practices assets
| Assets    |        |
|-----------|--------|
|IBM Storage Protect - Container Storage Pools and Data Deduplication - Best Practices | <ul><li>[Technical background, general guidelines, and best practices for using IBM Storage Protect container storage pool and data deduplication technologies](./best-practices/storage-protect/Container%20Storage%20Pools%20-%20Best%20Practices/Storage%20Protect%20Container%20Storage%20Pools%20-%20Best%20Practices.md)</li></ul> |


### Tools
| Assets    |        |
|-----------|--------|
| IBM Storage Protect - Client Workload Simulation tool | <ul><li>[`sp_client_load_gen.pl` - used to test scalability of IBM Storage Protect server sessions.](./tools/sp-load-generator/README.md)</li></ul> | 
| IBM Storage Protect - Disk Workload Simulation tool | <ul><li>[`sp_disk_load_gen.pl` - a benchmarking tool to identify performance issues with your hardware setup and configuration before/after installing IBM Storage Protect](./tools/sp-load-generator/README.md)</li></ul> | 
| Fakeload for IBM Storage Protect | <ul><li>[`fakeload` uses the Client API of IBM Storage Protect to efficiently `backup` and `restores` data.](./tools/sp-fakeload/README.md) </li></ul> |
| IBM Storage Protect Plus - Disk Workload Simulation tool | <ul><li>[`spp_disk_load_gen.pl` - used to evaluate the performance of storage used by vSnap prior to going in to production](./tools/spp-load-generator/README.md)</li></ul> |
| IBM Storage Protect - Cloud cache disk benchmarking tool | <ul><li>[`sp_disk_load_gen.pl` - disk benchmark tests to measure and validate the capability of the disk volumes underlying the IBM Storage Protect™ cloud accelerator cache.](./tools/sp-cloud-benchmark/docs/Cloud%20Cache%20and%20Object%20Storage%20Benchmark.md) | 
| IBM Storage Protect - Cloud Object storage benchmarking tool | <ul><li>[`sp_obj_storage_gen.pl` - a tool to benchmark the throughput of the server instance to the cloud object storage system, with a workload that is typical of IBM Storage Protect]((./tools/sp-cloud-benchmark/docs/Cloud%20Cache%20and%20Object%20Storage%20Benchmark.md))</li></ul> |
| IBM Storage Protect - Servermon tool| <ul><li>[`servermon.pl` - used to collect diagnostic data from the IBM Storage Protect Server, that can help troubleshoot problems with server processes, client sessions and of performance nature.](./tools/sp-servermon/README.md) </li></ul> |
| IBM Storage Protect - Audit a deduplicated file storage pool| <ul><li>[`dedupAuditTool.pl` - used to audit the referential integrity of the deduplicated storage pool](./tools/sp-de-dup-audit/README.md) </li></ul> |

---
## Support
The galaxy of assets related to IBM Storage Protect and IBM Storage Protect Plus offerings. Please follow the IBM support procedure for any issues with the deployment or usage of these assets in the context of the respective offering. This is the preferred method.

### Contribution

You are invited to contribute to this Blueprint, give feedback, and continuously improve its application.

---
## Licensing
Copyright 2022 IBM Corp.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

---