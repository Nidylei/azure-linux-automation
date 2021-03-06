﻿<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	try
	{
		$serverMachines = @()
		$serverMachinesHostNames = ""
		$noClient = $true
		$noServer = $true
		foreach ( $vmData in $allVMData )
		{
			if ( $vmData.RoleName -imatch "client" )
			{
				$clientVMData = $vmData
				$noClient = $false
			}
			elseif ( $vmData.RoleName -imatch "server" )
			{
				$serverMachines += $vmData
				$noServer = $fase
				if ( $serverMachinesHostNames )
				{
					$serverMachinesHostNames += ",$($vmData.RoleName):2181"
				}
				else
				{
					$serverMachinesHostNames += "$($vmData.RoleName):2181"
				}
			}
		}
		$serverMachinesHostNames = $serverMachinesHostNames.Trim()
		if ( $noClient )
		{
			Throw "No any master VM defined. Be sure that, Client VM role name matches with the pattern `"*master*`". Aborting Test."
		}
		if ( $noServer )
		{
			Throw "No any slave VM defined. Be sure that, Server machine role names matches with pattern `"*slave*`" Aborting Test."
		}
		#region CONFIGURE VM FOR TERASORT TEST
		LogMsg "CLIENT VM details :"
		LogMsg "  RoleName : $($clientVMData.RoleName)"
		LogMsg "  Public IP : $($clientVMData.PublicIP)"
		LogMsg "  SSH Port : $($clientVMData.SSHPort)"
		$i = 1
		foreach ( $vmData in $serverMachines )
		{
			LogMsg "SERVER #$i VM details :"
			LogMsg "  RoleName : $($vmData.RoleName)"
			LogMsg "  Public IP : $($vmData.PublicIP)"
			LogMsg "  SSH Port : $($vmData.SSHPort)"
			$i += 1
		}


		#
		# PROVISION VMS FOR LISA WILL ENABLE ROOT USER AND WILL MAKE ENABLE PASSWORDLESS AUTHENTICATION ACROSS ALL VMS IN SAME HOSTED SERVICE.	
		#
		ProvisionVMsForLisa -allVMData $allVMData
		
		foreach ( $vmData in $allVMData )
		{
			LogMsg "Adding $($vmData.InternalIP) $($vmData.RoleName) to /etc/hosts of $($clientVMData.RoleName) "
			$out = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "echo $($vmData.InternalIP) $($vmData.RoleName) >> /etc/hosts"
		}
		#endregion

		LogMsg "Generating constansts.sh ..."
		$constantsFile = "$LogDir\constants.sh"
		Set-Content -Value "#Generated by Azure Automation." -Path $constantsFile
		foreach ($zookeeperParam in $currentTestData.TestParameters.param )
		{
			Add-Content -Value "$zookeeperParam" -Path $constantsFile
			LogMsg "$zookeeperParam added to constansts.sh"
		}		
		Add-Content -Value "ZK_SERVERS=$serverMachinesHostNames" -Path $constantsFile
		LogMsg "ZK_SERVERS=$serverMachinesHostNames added to constants.sh"

		LogMsg "constanst.sh created successfully..."
		#endregion

		#region Download remote files needed to run tests
		LogMsg "Downloading remote files ..."

		$fileToUpload = ""
		foreach ( $fileURL in  $($currentTestData.remoteFiles).Split(",") )
		{
			LogMsg "Downloading $fileURL ..."
			$start_time = Get-Date
			$fileName =  $fileURL.Split("/")[$fileURL.Split("/").Count-1]
			$out = Invoke-WebRequest -Uri $fileURL -OutFile "$LogDir\$fileName"
			LogMsg "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
			if ( $fileToUpload )
			{
				$fileToUpload += ",.\$LogDir\$fileName"
			}
			else
			{
				$fileToUpload = ".\$LogDir\$fileName"
			}
		}
		#endregion
		
		#region EXECUTE TEST
		Set-Content -Value "/root/performance_zk.sh &> zkConsoleLogs.txt" -Path "$LogDir\StartZookeperTest.sh"
		RemoteCopy -uploadTo $clientVMData.PublicIP -port $clientVMData.SSHPort -files "$fileToUpload,.\$constantsFile,.\remote-scripts\performance_zk.sh,.\$LogDir\StartZookeperTest.sh" -username "root" -password $password -upload
		Remove-Item -Path "$LogDir\zookeeper.so" -Force 
		LogMsg "Removed zookeeper.so from $LogDir directory..."
		Remove-Item -Path "$LogDir\libzookeeper_mt.so.2" -Force 
		LogMsg "Removed libzookeeper_mt.so.2 from $LogDir directory..."
		Remove-Item -Path "$LogDir\zkclient.py" -Force 
		LogMsg "Removed zkclient.py from $LogDir directory..."
		Remove-Item -Path "$LogDir\zk-latencies.py" -Force 
		LogMsg "Removed zk-latencies.py from $LogDir directory..."
		$out = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "chmod +x *.sh"
		$out = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "mkdir -p lib.linux-x86_64-2.6 && mv zookeeper.so lib.linux-x86_64-2.6/zookeeper.so && mv libzookeeper_mt.so.2 lib.linux-x86_64-2.6/libzookeeper_mt.so.2"
		$testJob = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "/root/StartZookeperTest.sh" -RunInBackground
		#endregion

		#region MONITOR TEST
		while ( (Get-Job -Id $testJob).State -eq "Running" )
		{
			$currentStatus = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "tail -n 1 /root/zkConsoleLogs.txt"
			LogMsg "Current Test Staus : $currentStatus"
			WaitFor -seconds 10
		}
		
		$finalStatus = RunLinuxCmd -ip $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -command "cat /root/state.txt"
		
		RemoteCopy -downloadFrom $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "/root/zkConsoleLogs.txt"
		RemoteCopy -downloadFrom $clientVMData.PublicIP -port $clientVMData.SSHPort -username "root" -password $password -download -downloadTo $LogDir -files "/root/summary.log"
		$zookeeperSummary = Get-Content -Path "$LogDir\summary.log" -ErrorAction SilentlyContinue
		$zookeeperConsoleLogs = Get-Content -Path "$LogDir\zkConsoleLogs.txt" -ErrorAction SilentlyContinue
		LogMsg "************************ZOOKEEPER REPORT************************"
		foreach ( $line in $zookeeperConsoleLogs.Split("`n") )
		{
			if ( $line -imatch "Connected in ")
			{
				$printConsole = $true
			}
			elseif ( $line -imatch "Latency test complete")
			{
				LogMsg $line -LinuxConsoleOuput
				$printConsole = $false
			}
			if ( $printConsole )
			{
				LogMsg $line -LinuxConsoleOuput
			}
		}
		LogMsg "************************ZOOKEEPER REPORT************************"
		#endregion

		if (!$zookeeperSummary)
		{
			LogMsg "summary.log file is empty."
			$zookeeperSummary = "<EMPTY>"
		}
		if ( $finalStatus -imatch "TestFailed")
		{
			LogErr "Test failed. Last known status : $currentStatus."
			$testResult = "FAIL"
		}
		elseif ( $finalStatus -imatch "TestAborted")
		{
			LogErr "Test Aborted. Last known status : $currentStatus."
			$testResult = "ABORTED"
		}
		elseif ( $finalStatus -imatch "TestCompleted")
		{
			LogMsg "Test Completed."
			$testResult = "PASS"
		}
		elseif ( $finalStatus -imatch "TestRunning")
		{
			LogMsg "Powershell backgroud job for test is completed but VM is reporting that test is still running. Please check $LogDir\zkConsoleLogs.txt"
			LogMsg "Contests of summary.log : $zookeeperSummary"
			$testResult = "PASS"
		}
		LogMsg "Test result : $testResult"
		LogMsg "Test Completed"
	}
	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{
		$metaData = "ZooKeeper RESULT"
		if (!$testResult)
		{
			$testResult = "Aborted"
		}
		$resultArr += $testResult
		$resultSummary +=  CreateResultSummary -testResult $zookeeperResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
	}   
}

else
{
	$testResult = "Aborted"
	$resultArr += $testResult
}

$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed -ResourceGroups $isDeployed

#Return the result and summery to the test suite script..
return $result