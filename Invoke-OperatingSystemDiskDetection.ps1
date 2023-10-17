<#
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
#>

[CmdletBinding(SupportsShouldProcess=$True)]
  Param
    (
        [Parameter(Mandatory=$False)]
        [ValidateNotNullOrEmpty()]
        [Alias('BTEE')]
        [Regex]$BusTypeExclusionExpression = '(^USB$)',

        [Parameter(Mandatory=$False)]
        [ValidateNotNullOrEmpty()]
        [Alias('DST')]
        [UInt32]$DiskSizeThresholdInGB = 32
    )

Try
  {
        #Define variables
          $LoggingDetails = New-Object -TypeName 'System.Collections.Specialized.OrderedDictionary'    
            $LoggingDetails.Add('LogMessage', $Null)
            $LoggingDetails.Add('WarningMessage', $Null)
            $LoggingDetails.Add('ErrorMessage', $Null)
          $DateTimeMessageFormat = 'MM/dd/yyyy HH:mm:ss.FFF'  ###03/23/2022 11:12:48.347###
          [ScriptBlock]$GetCurrentDateTimeMessageFormat = {(Get-Date).ToString($DateTimeMessageFormat)}
          $OutputObjectProperties = New-Object -TypeName 'System.Collections.Specialized.OrderedDictionary'

          #Define the error handling definition
            [ScriptBlock]$ErrorHandlingDefinition = {
                                                        Param
                                                          (
                                                              [Int16]$Severity,
                                                              [Boolean]$Terminate
                                                          )
                                                        
                                                        If (($Null -ieq $Script:LASTEXITCODE) -or ($Script:LASTEXITCODE -eq 0))
                                                          {
                                                              [Int]$Script:LASTEXITCODE = 6000
                                                          }
                                                        
                                                        $ExceptionPropertyDictionary = New-Object -TypeName 'System.Collections.Specialized.OrderedDictionary'
                                                          $ExceptionPropertyDictionary.Add('Message', $_.Exception.Message)
                                                          $ExceptionPropertyDictionary.Add('Category', $_.Exception.ErrorRecord.FullyQualifiedErrorID)
                                                          $ExceptionPropertyDictionary.Add('LineNumber', $_.InvocationInfo.ScriptLineNumber)
                                                          $ExceptionPropertyDictionary.Add('LinePosition', $_.InvocationInfo.OffsetInLine)
                                                          $ExceptionPropertyDictionary.Add('Code', $_.InvocationInfo.Line.Trim())

                                                        $ExceptionMessageList = New-Object -TypeName 'System.Collections.Generic.List[String]'

                                                        ForEach ($ExceptionProperty In $ExceptionPropertyDictionary.GetEnumerator())
                                                          {
                                                              $ExceptionMessageList.Add("[$($ExceptionProperty.Key): $($ExceptionProperty.Value)]")
                                                          }

                                                        $LogMessageParameters = New-Object -TypeName 'System.Collections.Specialized.OrderedDictionary'
                                                          $LogMessageParameters.Message = $ExceptionMessageList -Join ' '
                                                          $LogMessageParameters.Verbose = $True
                              
                                                        Switch ($Severity)
                                                          {
                                                              {($_ -in @(1))} {Write-Verbose @LogMessageParameters}
                                                              {($_ -in @(2))} {Write-Warning @LogMessageParameters}
                                                              {($_ -in @(3))} {Write-Error @LogMessageParameters}
                                                          }

                                                        Switch ($Terminate)
                                                          {
                                                              {($_ -eq $True)}
                                                                {                  
                                                                    Throw
                                                                }
                                                          }
                                                    }
        
        #Import the required modules
          $RequiredModuleList = New-Object -TypeName 'System.Collections.Generic.List[String]'
            $RequiredModuleList.Add('Storage')
                                              
          ForEach ($RequiredModule In $RequiredModuleList)
            {
                Try
                  {
                      $RequiredModuleInfo = Try {Get-Module -Name ($RequiredModule)} Catch {$Null}
                                                  
                      Switch ($Null -ieq $RequiredModuleInfo)
                        {
                            {($_ -eq $True)}
                              {
                                  $LoggingDetails.LogMessage = "$($GetCurrentDateTimeMessageFormat.Invoke()) - Attempting to load required Module `"$($RequiredModule)`". Please Wait..."
                                  Write-Verbose -Message ($LoggingDetails.LogMessage) -Verbose
                                                  
                                  $Null = Import-Module -Name ($RequiredModule) -Force -DisableNameChecking
                              }
                        }
                  }
                Catch
                  {
                      $ErrorHandlingDefinition.Invoke(2, $True)
                  }
                Finally
                  {
                                                        
                  }
            }
      
        #Determine if a task sequence is running or not
          Try
            {
                [System.__ComObject]$TSEnvironment = New-Object -ComObject "Microsoft.SMS.TSEnvironment"
              
                If ($Null -ine $TSEnvironment)
                  {
                      $IsRunningTaskSequence = $True
                      
                      [Boolean]$IsConfigurationManagerTaskSequence = [String]::IsNullOrEmpty($TSEnvironment.Value("_SMSTSPackageID")) -eq $False
                      
                      Switch ($IsConfigurationManagerTaskSequence)
                        {
                            {($_ -eq $True)}
                              {
                                  $LoggingDetails.LogMessage = "$($GetCurrentDateTimeMessageFormat.Invoke()) - A Microsoft Endpoint Configuration Manager (MECM) task sequence was detected."
                                  Write-Verbose -Message ($LoggingDetails.LogMessage) -Verbose
                              }
                                      
                            {($_ -eq $False)}
                              {
                                  $LoggingDetails.LogMessage = "$($GetCurrentDateTimeMessageFormat.Invoke()) - A Microsoft Deployment Toolkit (MDT) task sequence was detected."
                                  Write-Verbose -Message ($LoggingDetails.LogMessage) -Verbose
                              }
                        }
                  }
            }
          Catch
            {
                $LoggingDetails.LogMessage = "$($GetCurrentDateTimeMessageFormat.Invoke()) - A task sequence was not detected."
                Write-Verbose -Message ($LoggingDetails.LogMessage) -Verbose
                
                $IsRunningTaskSequence = $False
            }
              
      #Define any scriptblocks for determining calculated properties
        [ScriptBlock]$DetermineMediaTypePriority = {
                                                      Switch -Regex ($_.MediaType)
                                                        {
                                                            '(^4$)|(^SSD$)' {1}
							    '(^3$)|(^HDD$)' {2}
							    '(^5$)|(^SCM$)' {3}
							    '(^0$)|(^Unspecified$)' {4}   
                                                        }
                                                   }

        [ScriptBlock]$DetermineBusTypePriority = {
                                                    Switch -Regex ($_.BusType)
                                                      {
                                                          '(^17$)|(^NVMe$)' {1}
						      	  '(^11$)|(^SATA$)' {2}
						      	  '(^8$)|(^RAID$)' {3}
						      	  '(^10$)|(^SAS$)' {4}
						      	  '(^12$)|(^SD$)' {5}
						      	  '(^7$)|(^USB$)' {6}
						      	  '(^1$)|(^SCSI$)' {7}
						      	  '(^6$)|(^Fibre Channel$)' {8}
						      	  '(^3$)|(^ATA$)' {9}
						      	  '(^15$)|(^File Backed Virtual$)' {10}
						      	  '(^2$)|(^ATAPI$)' {11}
						      	  '(^4$)|(^1394$)' {12}
						      	  '(^5$)|(^SSA$)' {13}
						      	  '(^9$)|(^iSCSI$)' {14}
						      	  '(^13$)|(^MMC$)' {15}
						      	  '(^14$)|(^MAX$)' {16}
						      	  '(^16$)|(^Storage Spaces$)' {17}
						      	  '(^0$)|(^Unknown$)' {18}
                                                          '(^18$)|(^Microsoft Reserved$)' {19}
                                                      }
                                                 }
      
      #Get the physical disks attached to the device
        $DiskPropertyList = New-Object -TypeName 'System.Collections.Generic.List[System.Object]'
          $DiskPropertyList.Add(@{Name = 'DiskNumber'; Expression = {$_.DeviceID}})
          $DiskPropertyList.Add('Manufacturer')
          $DiskPropertyList.Add('FriendlyName')
          $DiskPropertyList.Add('Model')
          $DiskPropertyList.Add('SerialNumber')
          $DiskPropertyList.Add('MediaType')
          $DiskPropertyList.Add(@{Name = 'MediaTypePriority'; Expression = ($DetermineMediaTypePriority)})
          $DiskPropertyList.Add('BusType')
          $DiskPropertyList.Add(@{Name = 'BusTypePriority'; Expression = ($DetermineBusTypePriority)})
          $DiskPropertyList.Add(@{Name = 'SizeInGB'; Expression = {[System.Math]::Round(($_.Size / 1GB), 2)}})

        $OutputObjectProperties.DiskList = Get-PhysicalDisk | Where-Object {($_.BusType -inotmatch $BusTypeExclusionExpression) -and ($_.Size -gt ($DiskSizeThresholdInGB / 1GB))} | Sort-Object -Property @('Size') | Select-Object -Property ($DiskPropertyList)
        $OutputObjectProperties.DiskListCount = ($OutputObjectProperties.DiskList | Measure-Object).Count
        $OutputObjectProperties.DesiredOperatingSystemDisk = $Null
        $OutputObjectProperties.DesiredOperatingSystemDiskLocated = $False
        $OutputObjectProperties.IsTaskSequenceRunning = $IsRunningTaskSequence

      $LoggingDetails.LogMessage = "$($GetCurrentDateTimeMessageFormat.Invoke()) - Detected $($OutputObjectProperties.DiskListCount) physical disk(s)."
      Write-Verbose -Message ($LoggingDetails.LogMessage) -Verbose

      Switch ($OutputObjectProperties.DiskListCount -gt 0)
        {
            {($_ -eq $True)}
              {                   
                  ForEach ($Disk In $OutputObjectProperties.DiskList)
                    {
                        $DiskLogMessageList = New-Object -TypeName 'System.Collections.Generic.List[System.String]'

                        ForEach ($DiskProperty In $Disk.PSObject.Properties)
                          {
                              $DiskPropertyLogMessage = "[$($DiskProperty.Name): $($DiskProperty.Value)]"
                              
                              $DiskLogMessageList.Add($DiskPropertyLogMessage)
                          }

                        $DiskLogMessage = $DiskLogMessageList -Join ' '

                        $LoggingDetails.LogMessage = "$($GetCurrentDateTimeMessageFormat.Invoke()) - $($DiskLogMessage)"
                        Write-Verbose -Message ($LoggingDetails.LogMessage) -Verbose
                    }
                  
                  $DiskListByMediaTypePriority = $OutputObjectProperties.DiskList | Group-Object -Property 'MediaTypePriority' | Sort-Object -Property {[UInt32]::Parse($_.Name)}
            
                  :MediaTypePriorityLoop ForEach ($MediaTypePriority In $DiskListByMediaTypePriority)
                    {
                        Switch ($MediaTypePriority.Count -gt 0)
                          {
                              {($_ -eq $True)}
                                {
                                    $MediaTypePriorityGroup = $MediaTypePriority.Group

                                    $MediaTypePriorityGroupName = $MediaTypePriorityGroup[0].MediaType
                          
                                    $LoggingDetails.LogMessage = "$($GetCurrentDateTimeMessageFormat.Invoke()) - Attempting to process media type group `"$($MediaTypePriorityGroupName)`" [Priority: $($MediaTypePriority.Name)]. Please Wait..."
                                    Write-Verbose -Message ($LoggingDetails.LogMessage) -Verbose
                          
                                    $DiskListByBusTypePriority = $MediaTypePriorityGroup | Group-Object -Property 'BusTypePriority' | Sort-Object -Property {[UInt32]::Parse($_.Name)}

                                    :BusTypePriorityLoop ForEach ($BusTypePriority In $DiskListByBusTypePriority)
                                      {
                                          $BusTypePriorityGroup = $BusTypePriority.Group

                                          $BusTypePriorityGroupName = $BusTypePriorityGroup[0].BusType
                                
                                          $LoggingDetails.LogMessage = "$($GetCurrentDateTimeMessageFormat.Invoke()) - Attempting to process bus type group `"$($BusTypePriorityGroupName)`" [Priority: $($BusTypePriority.Name)]. Please Wait..."
                                          Write-Verbose -Message ($LoggingDetails.LogMessage) -Verbose

                                          Switch ($BusTypePriority.Count -gt 0)
                                            {
                                                {($_ -eq $True)}
                                                  {
                                                      $OutputObjectProperties.DesiredOperatingSystemDisk = $BusTypePriorityGroup | Select-Object -First 1

                                                      Switch ($Null -ine $OutputObjectProperties.DesiredOperatingSystemDisk)
                                                        {
                                                            {($_ -eq $True)}
                                                              {
                                                                  $LoggingDetails.LogMessage = "$($GetCurrentDateTimeMessageFormat.Invoke()) - The desired operating system disk was found in media type group `"$($MediaTypePriorityGroupName)`" [Priority: $($MediaTypePriority.Name)] and bus type group `"$($BusTypePriorityGroupName)`" [Priority: $($BusTypePriority.Name)]."
                                                                  Write-Verbose -Message ($LoggingDetails.LogMessage) -Verbose
                                      
                                                                  $OutputObjectProperties.DesiredOperatingSystemDiskLocated = $True

                                                                  Break MediaTypePriorityLoop
                                                              }
                                                        }
                                                  }
                                            }
                                      }
                                }
                          }
                    }

                  Switch ($OutputObjectProperties.DesiredOperatingSystemDiskLocated)
                    {
                        {($_ -eq $True)}
                          {
                              ForEach ($DesiredOperatingSystemDiskProperty In $OutputObjectProperties.DesiredOperatingSystemDisk.PSObject.Properties)
                                {
                                    $LoggingDetails.LogMessage = "$($GetCurrentDateTimeMessageFormat.Invoke()) - $($DesiredOperatingSystemDiskProperty.Name): $($DesiredOperatingSystemDiskProperty.Value -Join ', ')"
                                    Write-Verbose -Message ($LoggingDetails.LogMessage) -Verbose
                                }

                              Switch ($IsRunningTaskSequence)
                                {
                                    {($_ -eq $True)}
                                      {
                                          $TSVariableDictionary = New-Object -TypeName 'System.Collections.Specialized.OrderedDictionary'
                                            $TSVariableDictionary.'OSDDiskIndex' = $OutputObjectProperties.DesiredOperatingSystemDisk.DiskNumber
                                            $TSVariableDictionary.'OSDiskNumber' = $OutputObjectProperties.DesiredOperatingSystemDisk.DiskNumber
                                            $TSVariableDictionary.'OSDDiskCount' = $OutputObjectProperties.DiskListCount

                                          ForEach ($TSVariable In $TSVariableDictionary.GetEnumerator())
                                            {
                                                $LoggingDetails.LogMessage = "$($GetCurrentDateTimeMessageFormat.Invoke()) - Attempting to the value of task sequence variable `"$($TSVariable.Key)`" to `"$($TSVariable.Value)`". Please Wait..."
                                                Write-Verbose -Message ($LoggingDetails.LogMessage) -Verbose

                                                $TSEnvironment.Value($TSVariable.Key) = $TSVariable.Value
                                            }
                                      }
                                }
                          }
                    }
              }
        }
  }
Catch
  {
      $ErrorHandlingDefinition.Invoke(2, $True)
  }
Finally
  {
      $OutputObject = New-Object -TypeName 'System.Management.Automation.PSObject' -Property ($OutputObjectProperties)

      Write-Output -InputObject ($OutputObject)
  }
