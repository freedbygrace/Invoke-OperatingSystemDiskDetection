Try
  {
      #Initialize the task sequence environment
        Try {[System.__ComObject]$TSEnvironment = New-Object -ComObject "Microsoft.SMS.TSEnvironment"} Catch {}

      #Define variable(s)
        [Regex]$BusTypeExclusions = "(^USB$)"
        [String[]]$RequiredModules = @("Storage")
        
        $IsUEFI = [Boolean]::Parse($TSEnvironment.Value('_SMSTSBootUEFI'))
        $LogMessage = "IsUEFI = $($IsUEFI.ToString())"
        Write-Verbose -Message "$($LogMessage)" -Verbose
        
        [UInt32]$OperatingSystemDiskNumber = $TSEnvironment.Value('OSDDiskIndex')
        $LogMessage = "Operating System Disk Number = $($OperatingSystemDiskNumber)"
        Write-Verbose -Message "$($LogMessage)" -Verbose
        
        $LogMessage = "Operating System disk WILL NOT be wiped because it has already been formatted by the operating system deployment solution."
        Write-Verbose -Message "$($LogMessage)" -Verbose
      
      #Import required module(s)
        ForEach ($RequiredModule In $RequiredModules)
          {
              If (!(Get-Module -Name $RequiredModule))
                {
                    $Null = Import-Module -Name ($RequiredModule) -DisableNameChecking -Force -ErrorAction Stop
                }
          }
      
      #Get the physical disks attached to the device
        $PhysicalDisks = Get-PhysicalDisk | Where-Object {($_.BusType -inotmatch $BusTypeExclusions.ToString())} | Sort-Object -Property @('Size')

      #Measure the amount of physical disks detected within the device (Ensure that storage interface(s) are not disabled within the BIOS settings)  
        $PhysicalDiskCount = $PhysicalDisks | Measure-Object | Select-Object -ExpandProperty Count

      #Determine the disk that will store the operating system
        $OperatingSystemDisk = $PhysicalDisks | Where-Object {($_.DeviceID -ieq $OperatingSystemDiskNumber)}

      #Determine the disk(s) that will not store the operating system
        $DataDisks = $PhysicalDisks | Where-Object {($_.DeviceID -ine $OperatingSystemDisk.DeviceID)}
        $DataDiskCount = $DataDisks | Measure-Object | Select-Object -ExpandProperty Count

      #Get the partitions/volume(s) on the disk
        If ($DataDiskCount -gt 0)
          {
              ForEach ($DataDisk In $DataDisks)
                {    
                    [Int]$DataDiskNumber = $DataDisk.DeviceID
                    
                    [String]$DataDiskVolumeName = "DATA00$($DataDiskNumber)"
                
                    $TaskSequenceVariableName = "OSDFormatDataDisk00$($DataDiskNumber)"
                    
                    $TSEnvironment.Value($TaskSequenceVariableName) = "False"
                                  
                    [ScriptBlock]$GetDataDiskInfo = {Get-Disk -Number ($DataDiskNumber)}
                    
                    [ScriptBlock]$FormatAndPartitionDisk = {
                                                              #Clean the disk and format it according to the specification(s)
                                                                Switch ($IsUEFI)
                                                                  {
                                                                      {($_ -eq $True)}
                                                                        {
                                                                            $PartitionStyle = [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]::GPT
                                                                        }
                                                      
                                                                      {($_ -eq $False)}
                                                                        {
                                                                            $PartitionStyle = [Microsoft.PowerShell.Cmdletization.GeneratedTypes.Disk.PartitionStyle]::MBR
                                                                        }
                                                                  }
                                                
                                                                #Perform disk partitioning and formatting
                                                                  [String]$ActivityMessage = "Attempting to format and partition data disk $($DataDiskNumber). Please Wait..."
                                                                  
                                                                  [String]$StatusMessage = "$($ActivityMessage)"
                                                                  
                                                                  [Int]$ProgressID = 1
                                                                  
                                                                  Write-Progress -ID ($ProgressID) -Activity ($ActivityMessage) -Status ($StatusMessage)
                                                                
                                                                  Switch ($GetDataDiskInfo.Invoke())
                                                                    {
                                                                        {($_.PartitionStyle -imatch "(^RAW$)")}
                                                                          {
                                                                              $Null = Initialize-Disk -InputObject ($GetDataDiskInfo.Invoke()) -PartitionStyle ($PartitionStyle) -PassThru -Confirm:$False -Verbose
                                                                          }
                                                                                
                                                                        {($_.PartitionStyle -inotmatch "(^RAW$)")}
                                                                          {
                                                                              $Null = Clear-Disk -InputObject ($GetDataDiskInfo.Invoke()) -RemoveData -Confirm:$False -PassThru -Verbose
                                                                              $Null = Initialize-Disk -InputObject ($GetDataDiskInfo.Invoke()) -PartitionStyle ($PartitionStyle) -PassThru -Confirm:$False -Verbose
                                                                          }       
                                                                    }
                                                                        
                                                                  $Null = New-Partition -InputObject ($GetDataDiskInfo.Invoke()) -UseMaximumSize -AssignDriveLetter -Verbose | Format-Volume -FileSystem NTFS -NewFileSystemLabel ($DataDiskVolumeName) -Confirm:$False -Verbose
      
                                                                  Write-Progress -ID ($ProgressID) -Activity ($ActivityMessage) -Completed
                                                           }

                    #Clean the disk and format it according to the specification(s)
                      $FormatAndPartitionDisk.Invoke()
                }
          }
  }
Catch
  {
      Write-Error -ErrorRecord ($_)
  }
