﻿#======================================================================================================================#
#                                                                                                                      #
#  AzureSynapseScriptsAndAccelerators - PowerShell and T-SQL Utilities                                                 #
#                                                                                                                      #
#  This utility was developed to aid SMP/MPP migrations to Azure Synapse Migration Practitioners.                      #
#  It is not an officially supported Microsoft application or tool.                                                    #
#                                                                                                                      #
#  The utility and any script outputs are provided on "AS IS" basis and                                                #
#  there are no warranties, express or implied, including, but not limited to implied warranties of merchantability    #
#  or fitness for a particular purpose.                                                                                #
#                                                                                                                      #                    
#  The utility is therefore not guaranteed to generate perfect code or output. The output needs carefully reviewed.    #
#                                                                                                                      #
#                                       USE AT YOUR OWN RISK.                                                          #
#                                                                                                                      #
#======================================================================================================================#
#
# =================================================================================================================================================
# Description:
#       Use this to extract Views/Functions/StoredProcs DDL scripts from SQL Server. 
#       Parameters driven configuration files are the input of this powershell scripts 
# =================================================================================================================================================
# =================================================================================================================================================
# 
# Authors: Andrey Mirskiy
# Tested with Azure Synaspe Analytics and SQL Server 2017 
# 
# Use this to set Powershell permissions (examples)
# Set-ExecutionPolicy Unrestricted -Scope CurrentUser 
# Unblock-File -Path .\ExtractCodeDDLs.ps1


#Requires -Version 5.1
#Requires -Modules SqlServer


Function GetPassword([SecureString] $securePassword) {
	$securePassword = Read-Host "Password" -AsSecureString
	$P = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
	return $P
}


Function ExportObjectDDLs() {
    [CmdletBinding()] 
    param( 
        [Parameter(Position = 1, Mandatory = $true)] [array]$Objects, 
        [Parameter(Position = 2, Mandatory = $true)] [string]$OutputDatabaseFolder,
        [Parameter(Position = 3, Mandatory = $true)] [string]$Subfolder,
        [Parameter(Position = 4, Mandatory = $true)] [string]$ObjectType
    ) 

    $currObjects = $Objects | Where-Object {$_.type_desc -eq $ObjectType}
    foreach ($object in $currObjects) {
        $outputFolderPath = Join-Path -Path $OutputDatabaseFolder -ChildPath $Subfolder
        if (!(Test-Path $outputFolderPath)) {
            New-Item -Path $outputFolderPath -ItemType Directory -Force | Out-Null
        }

        $outputfilePath = Join-Path -Path $outputFolderPath -ChildPath $object.file_name
        (Get-Date -Format HH:mm:ss.fff)+" - "+$outputfilePath | Write-Host -ForegroundColor Yellow
        $object.definition | Out-File -FilePath $outputFilePath
    }
}


Function Get-AbsolutePath
{
    [CmdletBinding()] 
    param( 
        [Parameter(Position=0, Mandatory=$true)] [string]$Path
    ) 

    if ([System.IO.Path]::IsPathRooted($Path) -eq $false) {
        return [IO.Path]::GetFullPath( (Join-Path -Path $PSScriptRoot -ChildPath $Path) )
    } else {
        return $Path
    }
}



########################################################################################
#
# Main Program Starts here
#
########################################################################################

Import-Module -Name SqlServer

$ProgramStartTime = Get-Date

$ScriptPath = $PSScriptRoot 

# Default Database configuration File Name
$defaultDatabaseConfigFileName = "DatabasesList.csv"
# Default JSON configuration File Name
$defaultJsonConfigFileName = "ExtractCodeDDLs_config.json"


$DatabaseConfigFileName = Read-Host -prompt "Enter the Databases List file name or press 'Enter' to accept the default [$($defaultDatabaseConfigFileName)]"
if ([string]::IsNullOrWhiteSpace($databaseConfigFileName)) {
    $DatabaseConfigFileName = $defaultDatabaseConfigFileName
}

$DatabaseConfigFileFullPath = Join-Path -Path $ScriptPath -ChildPath $DatabaseConfigFileName
    

if (!(Test-Path $DatabaseConfigFileFullPath )) {
    Write-Host "Could not find Databases List file: $DatabaseConfigFileFullPath " -ForegroundColor Red
    break 
}


$jsonConfigFileName = Read-Host -prompt "Enter the Config file name or press 'Enter' to accept the default [$($defaultJsonConfigFileName)]"
if([string]::IsNullOrWhiteSpace($jsonConfigFileName)) {
    $jsonConfigFileName = $defaultJsonConfigFileName
}

$JsonConfigFileFullPath = Join-Path -Path $ScriptPath -ChildPath $jsonConfigFileName
if (!(Test-Path $JsonConfigFileFullPath )) {
    Write-Host "Could not find Config file: $JsonConfigFileFullPath " -ForegroundColor Red
    break 
}
    
$JsonConfig = Get-Content -Path $JsonConfigFileFullPath | ConvertFrom-Json 
    
$SqlServerName = $JsonConfig.ServerName
$UseIntegrated =  $JsonConfig.IntegratedSecurity
$OutputBaseFolder = Get-AbsolutePath $JsonConfig.OutputFolder


if ( ($UseIntegrated.ToUpper() -eq "YES") -or ($UseIntegrated.ToUpper() -eq "Y") )  
{
    $UseIntegratedSecurity = $true
}
else 
{
	Write-Host "Need Login Information..." -ForegroundColor Yellow
	$UseIntegratedSecurity = $false
	$UserName = Read-Host -prompt "Enter the User Name to connect to the SQL Server"
  
	if ([string]::IsNullOrWhiteSpace($UserName)) {
		Write-Host "A user name must be entered" -ForegroundColor Red
		break
	}
	$Password = GetPassword
	if ([string]::IsNullOrWhiteSpace($Password)) {
		Write-Host "A password must be entered." -ForegroundColor Red
		break
	}
}


try {      
    $databasesList = Import-Csv $DatabaseConfigFileFullPath

    foreach ($row in $databasesList) {
        if ($row.Active -ne 1) {
            continue
        }

        $SourceDatabase = $row.SourceDatabase
	    $OutputDatabaseFolder = Join-Path -Path $OutputBaseFolder -ChildPath $SourceDatabase

        $sqlModulesDefinition = "select OBJECT_SCHEMA_NAME(m.object_id)+'.'+OBJECT_NAME(m.object_id)+'.sql' as file_name, OBJECT_SCHEMA_NAME(m.object_id) as schema_name, OBJECT_NAME(m.object_id) as object_name, m.object_id, o.type, o.type_desc, m.definition
            from sys.sql_modules m join sys.objects o on m.object_id=o.object_id"

        if ($UseIntegratedSecurity) {
            $resultset = Invoke-Sqlcmd -Query $sqlModulesDefinition -ServerInstance $SqlServerName -database $SourceDatabase -OutputAs DataTables -MaxCharLength ([int]::MaxValue)
        }
        else 
        {   
            $resultset = Invoke-Sqlcmd -Query $sqlModulesDefinition -ServerInstance $SqlServerName -database $SourceDatabase -Username $UserName -Password $Password -OutputAs DataTables -MaxCharLength ([int]::MaxValue)
        }

        ExportObjectDDLs -Objects $resultset -OutputDatabaseFolder $OutputDatabaseFolder -Subfolder "Views"       -ObjectType "VIEW"
        ExportObjectDDLs -Objects $resultset -OutputDatabaseFolder $OutputDatabaseFolder -Subfolder "StoredProcs" -ObjectType "SQL_STORED_PROCEDURE"
        ExportObjectDDLs -Objects $resultset -OutputDatabaseFolder $OutputDatabaseFolder -Subfolder "Triggers"    -ObjectType "SQL_TRIGGER"
        ExportObjectDDLs -Objects $resultset -OutputDatabaseFolder $OutputDatabaseFolder -Subfolder "Functions"   -ObjectType "SQL_SCALAR_FUNCTION"
        ExportObjectDDLs -Objects $resultset -OutputDatabaseFolder $OutputDatabaseFolder -Subfolder "Functions"   -ObjectType "SQL_INLINE_TABLE_VALUED_FUNCTION"
        ExportObjectDDLs -Objects $resultset -OutputDatabaseFolder $OutputDatabaseFolder -Subfolder "Functions"   -ObjectType "SQL_TABLE_VALUED_FUNCTION"
    }    
}
catch [Exception] {
    Write-Warning $_.Exception.Message
}


$ProgramFinishTime = Get-Date

Write-Host "Program Start Time:   ", $ProgramStartTime -ForegroundColor Magenta
Write-Host "Program Finish Time:  ", $ProgramFinishTime -ForegroundColor Magenta
Write-Host "Program Elapsed Time: ", ($ProgramFinishTime-$ProgramStartTime) -ForegroundColor Magenta
