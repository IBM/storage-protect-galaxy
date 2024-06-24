## Appendix F. Troubleshooting

At the time of publication, the following issue was known.

### Slow throughput after server installation
In some cases, following a new installation of IBM Storage Protect, the server might experience slow throughput. This condition can be caused by a delay in the Db2 runstats operation, which optimizes how queries are performed. An indication of this issue is that the Db2 process db2sysc is using a large amount of CPU processing as compared to the amount of processing that is used by the server.

To resolve this problem, you can start runstats processing manually. Issue the following command from the administrative command-line interface:
```
dsmadmc > runstats all
```