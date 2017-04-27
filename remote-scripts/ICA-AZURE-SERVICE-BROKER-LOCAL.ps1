<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force

try
{
	$result = ""
	$testResult = ""
	$isDeployed = ""
	$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
	if ($isDeployed)
	{
		$hs1VIP = $AllVMData.PublicIP
		$hs1vm1sshport = $AllVMData.SSHPort
		$hs1ServiceUrl = $AllVMData.URL
		$hs1vm1Dip = $AllVMData.InternalIP
		$environment = $xmlConfig.config.Azure.General.Environment
		$subscriptionID = $xmlConfig.config.Azure.General.SubscriptionID
		$spTenantID = $env:ServicePrincipalTenantID
		$spClientID = $env:ServicePrincipalClientID
		$spClientSecret = $env:ServicePrincipalkey
		
		$resourceGroupName = "rg-sqlserver-$(get-random)"
		$sqlServerName = "server-$(get-random)"
		$location = (Get-AzureRmLocation | select Location | Get-Random).location
		
		foreach ($file in $currentTestData.files.Split(","))
		{
			LogMsg "Update test script $file"
			$contents = Get-Content .\remote-scripts\$file -raw
			$contents -replace 'REPLACE_WITH_RESOURCEGROUPNAME',$resourceGroupName`
			-replace 'REPLACE_WITH_LOCATION',$location`
			-replace 'REPLACE_WITH_ENVIRONMENT',$environment`
			-replace 'REPLACE_WITH_SUBSCRIPTIONID',$subscriptionID`
			-replace 'REPLACE_WITH_TENANTID',$spTenantID`
			-replace 'REPLACE_WITH_CLIENTID',$spClientID`
			-replace 'REPLACE_WITH_CLIENTSECRET',$spClientSecret`		
			-replace 'REPLACE_WITH_SERVERNAME',$sqlServerName | out-file $file -Encoding default
		}

		RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo
		LogMsg "Executing : create-sql-rg.sh"
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "./create-sql-rg.sh > create-sql-rg.log 2>&1" -runAsSudo -runMaxAllowedTime 1200

		RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/meta-azure-service-broker/lib/broker/db/sqlserver/schema.sql" -downloadTo .\ -port $hs1vm1sshport -username $user -password $password
		
		LogMsg "Run a SQL command to create tables"
		$SQLfile ="$PWD\schema.sql"
		$connectionString = "Server=tcp:$sqlServerName.database.windows.net,1433;Initial Catalog=mySampleDatabase;Persist Security Info=False;User ID=ServerAdmin;Password=p@ssw0rdUser@123;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
		$connection = New-Object -TypeName System.Data.SqlClient.SqlConnection($connectionString)
		$query = [IO.File]::ReadAllText($sqlFile)
		$command = New-Object -TypeName System.Data.SqlClient.SqlCommand($query, $connection)
		$connection.Open()
		$command.ExecuteNonQuery()
		$connection.Close()
		
		LogMsg "Executing : $($currentTestData.testScript)"
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "./$($currentTestData.testScript) | tee $($currentTestData.testScript).log" -runAsSudo -runMaxAllowedTime 5400
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "zip -r service-broker-logfile.zip meta-azure-service-broker/coverage/" -runAsSudo -ignoreLinuxExitCode
		#RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mv Runtime.log $($currentTestData.testScript).log" -runAsSudo
		RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/create-sql-rg.log, /home/$user/service-broker-logfile.zip, /home/$user/$($currentTestData.testScript).log" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password
		$testResult = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $($currentTestData.testScript).log.log  | grep -i '[0-9]\{2,3\} passing'" -runAsSudo
		$passResult = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $($currentTestData.testScript).log.log  | grep -i '[0-9]\{2,3\} passing' |  wc -l" -runAsSudo
		$failResult = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $($currentTestData.testScript).log.log  | grep -i '[0-9]\{2,3\} passing' | grep fail | wc -l" -runAsSudo
		LogMsg "Test result summary:"
		Out-Host -InputObject $testResult
		if (($passResult -eq 2) -and ($failResult -eq 0))
		{
			$testResult = 'PASS'
			LogMsg "Remove resource group $resourceGroupName"			
			Remove-AzureRmResourceGroup -ResourceGroupName $resourceGroupName -Force -Verbose
		}
		else
		{
			LogMsg "Test FAIL, please check log $LogDir\$($currentTestData.testScript).log for details"
			$testResult = 'FAIL'
		}
		LogMsg "Test result : $testResult"
	}
	else
	{
		$testResult = "Aborted"
		$resultArr += $testResult
	}
}
catch
{
	$ErrorMessage =  $_.Exception.Message
	LogMsg "EXCEPTION : $ErrorMessage"   
}
Finally
{
	$metaData = ""
	if (!$testResult)
	{
		$testResult = "Aborted"
	}
	$resultArr += $testResult
}   

#Clean up the setup
DoTestCleanUp -result $testResult -testName $currentTestData.testName -deployedServices $isDeployed -ResourceGroups $isDeployed


$result = GetFinalResultHeader -resultarr $resultArr


#Return the result and summery to the test suite script..
return $result