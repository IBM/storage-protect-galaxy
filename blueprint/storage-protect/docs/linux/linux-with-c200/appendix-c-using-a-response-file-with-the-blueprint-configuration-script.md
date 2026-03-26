## Appendix C. Using a response file with the Blueprint configuration script

You can run the Blueprint configuration script in non-interactive mode by using a response file to set your
configuration choices.

Three response files are provided with the Blueprint configuration script. If you plan to set up a system by
using all default values, you can run the configuration script in non-interactive mode by using one of the
following response files:
* **Small system**
  * ./response-files/responsefilesmall.txt
* **Medium system**
  * ./response-files/responsefilemed.txt
* **Large system**
  * Storwize systems: ./response-files/responsefilelarge.txt
  * IBM Elastic Storage System systems: ./response-files/responsefile_ess.txt

The files are pre-filled with default configuration values for the small, medium, and large systems and do not require updates.

If you want to customize your responses for a system, use the following table with your ["Planning worksheets"](#22-planning-worksheets) to update one of the default response files. The values that are used in the response file correspond to values that you recorded in the _Your value_ column of the worksheet.

| Response file value | Corresponding value from the planning worksheet |
|---------------------|-------------------------------------------------|
| serverscale         | Not recorded in the planning worksheet. Enter a value of S for a small system, M for a medium system, or L for a large system. |
| db2user             | Db2 instance owner ID                           |
| db2userpw           | Db2 instance owner password                     |
| db2group            | Primary group for the Db2 instance owner ID     |
| db2userhomedir      | Home directory for the Db2 instance owner ID. By default, this directory is created in the /home file system. </br> For IBM Elastic Storage System configurations, the preferred method is to use a directory in the shared IBM Storage Scale file system. |
| instdirmountpoint   | Directory for the server instance               |
| db2dirpaths         | Directories for the database                    |
| tsmstgpaths         | Directories for storage                         |
| actlogpath          | Directory for the active log                    |
| archlogpath         | Directory for the archive log                   |
| dbbackdirpaths      | Directories for database backup                 |
| backupstarttime     | Schedule start time                             |
| tsmsysadminid       | IBM Storage Protect administrator ID           |
| tsmsysadminidpw     | IBM Storage Protect administrator ID password  |
| tcpport             | TCP/IP port address for communications with the IBM Storage Protect server. |
| servername          | Server name                                     |
| serverpassword      | Server password                                 |
