# Invoke-OperatingSystemDiskDetection
.SYNOPSIS

Dynamically determines the desired operating system disk based on a calculated MediaType and BusType priority.

.DESCRIPTION
This solves for issues in devices that have multiple hard disk(s) where operating system gets installed onto the incorrect disk.
This method bypasses any manual determination required across all models and devices.
                
.PARAMETER BusTypeExclusionExpression
A valid regular expression to exclude disks for from consideration based on their bus type. By default, USB based disks will be excluded.

.NOTES
By default, the operating system will get deployed onto the fatest and smallest disk.
If a task sequence is running, the required task sequence variables (More can be added) will be configured so that the Format and Partition steps will format the correct hard disk.

.LINK
https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/msft-Disk
