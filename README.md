# Invoke-OperatingSystemDiskDetection
Dynamically determines the desired operating system disk based on a calculated MediaType and BusType priority.
This solves for issues in devices that have multiple hard disk(s) where operating system gets installed onto the incorrect disk.
This method bypasses any manual determination required across all models and devices.
By default, the operating system will get deployed onto the fatest and smallest disk.
If a task sequence is running, the required task sequence variables (More can be added) will be configured so that the Format and Partition steps will format the correct hard disk.

https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/msft-Disk
