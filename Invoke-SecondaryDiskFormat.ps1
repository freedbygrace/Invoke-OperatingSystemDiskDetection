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
                    [System.Int32]$DataDiskNumber = $DataDisk.DeviceID
                    
                    [String]$DataDiskVolumeName = "DATA$($DataDiskNumber.ToString('000'))"
                
                    $TaskSequenceVariableName = "OSDFormatDataDisk$($DataDiskNumber.ToString('000'))"
                    
                    $TSEnvironment.Value($TaskSequenceVariableName) = "False"
                                  
                    [ScriptBlock]$GetDataDiskInfo = {
                                                        Param
                                                          (
                                                              [System.Int32]$DiskNumber
                                                          )
                                                        
                                                        Write-Output -InputObject (Get-Disk -Number ($DiskNumber))
                                                    }
                    
                    [ScriptBlock]$FormatAndPartitionDisk = {
                                                              Param
                                                                (
                                                                    [System.Int32]$DiskNumber
                                                                )
                                                              
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
                                                                  [String]$ActivityMessage = "Attempting to format and partition data disk $($DiskNumber). Please Wait..."
                                                                  
                                                                  [String]$StatusMessage = "$($ActivityMessage)"
                                                                  
                                                                  [Int]$ProgressID = 1
                                                                  
                                                                  Write-Progress -ID ($ProgressID) -Activity ($ActivityMessage) -Status ($StatusMessage)
                                                                
                                                                  Switch ($GetDataDiskInfo.Invoke($DiskNumber))
                                                                    {
                                                                        {($_.PartitionStyle -imatch "(^RAW$)")}
                                                                          {
                                                                              $Null = Initialize-Disk -InputObject ($GetDataDiskInfo.Invoke($DiskNumber)) -PartitionStyle ($PartitionStyle) -PassThru -Confirm:$False -Verbose
                                                                          }
                                                                                
                                                                        {($_.PartitionStyle -inotmatch "(^RAW$)")}
                                                                          {
                                                                              $Null = Clear-Disk -InputObject ($GetDataDiskInfo.Invoke($DiskNumber)) -RemoveData -Confirm:$False -PassThru -Verbose
                                                                              $Null = Initialize-Disk -InputObject ($GetDataDiskInfo.Invoke($DiskNumber)) -PartitionStyle ($PartitionStyle) -PassThru -Confirm:$False -Verbose
                                                                          }       
                                                                    }
                                                                        
                                                                  $Null = New-Partition -InputObject ($GetDataDiskInfo.Invoke($DiskNumber)) -UseMaximumSize -AssignDriveLetter -Verbose | Format-Volume -FileSystem NTFS -NewFileSystemLabel ($DataDiskVolumeName) -Confirm:$False -Verbose
      
                                                                  Write-Progress -ID ($ProgressID) -Activity ($ActivityMessage) -Completed
                                                           }

                    #Determine if the disk should be formatted
                      Switch ($True)
                        {
                            {(($GetDataDiskInfo.Invoke($DataDiskNumber)).NumberOfPartitions -gt 0)}
                              {
                                  $DataDiskVolumes = $GetDataDiskInfo.Invoke($DataDiskNumber) | Get-Partition | Get-Volume | Where-Object {($_.DriveLetter -imatch "(^[a-zA-Z]$)")}

                                  $DataDiskVolumeCount = $DataDiskVolumes | Measure-Object | Select-Object -ExpandProperty Count

                                  Switch ($DataDiskVolumeCount -gt 0)
                                    {
                                        {($_ -eq $True)}
                                          {
                                              :DataDiskVolumeLoop ForEach ($DataDiskVolume In $DataDiskVolumes)
                                                {
                                                    $FoldersInVolumeRoot = Get-ChildItem -Path "$($DataDiskVolume.DriveLetter):\" -Force | Where-Object {($_ -is [System.IO.DirectoryInfo])}

                                                    Switch ($True)
                                                      {
                                                          {($FoldersInVolumeRoot.Name -imatch "(^Windows$)|(^Windows\.Old$)")}
                                                            {
                                                                #Set the value of the 'OSDFormatDataDisk' variable which will tell the task sequence that this disk is ok to wipe
                                                                  $TSEnvironment.Value($TaskSequenceVariableName) = "True"
                                              
                                                                $LogMessage = "Disk $($DataDiskNumber) will be wiped and formatted because a previous Windows installation was detected and could cause errors with the installation of the new operating system."
                                                                Write-Verbose -Message "$($LogMessage)" -Verbose
                                              
                                                                #Clean the disk and format it according to the specification(s)
                                                                  $FormatAndPartitionDisk.Invoke($DataDiskNumber)

                                                                #Exit the for loop because at least one volume has already met the requirements for the disk to be formatted
                                                                  Break DataDiskVolumeLoop
                                                            }
                                                      }
                                                }
                                          }
                                    }
                              }

                            {(($GetDataDiskInfo.Invoke($DataDiskNumber).NumberOfPartitions -eq 0) -or ($GetDataDiskInfo.Invoke($DataDiskNumber).PartitionStyle -imatch '^RAW$'))}
                              {
                                  $LogMessage = "Disk $($DataDiskNumber) will be wiped and formatted because no partition(s) or volume(s) could be found. The disk has not been provisioned."
                                  Write-Verbose -Message "$($LogMessage)" -Verbose
                      
                                  #Set the value of the 'OSDFormatDataDisk' variable which will tell the task sequence that this disk is ok to wipe
                                    $TSEnvironment.Value($TaskSequenceVariableName) = "True"
                            
                                  #Clean the disk and format it according to the specification(s)
                                    $FormatAndPartitionDisk.Invoke($DataDiskNumber)
                              }
                        }
                }
          }
  }
Catch
  {
      Write-Error -ErrorRecord ($_)
  }