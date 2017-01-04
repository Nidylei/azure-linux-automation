<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$resultArr = @()
$allTestStatistics = @()
function CreateTestResultObject()
{
	$TestStatistics = New-Object -TypeName PSObject
	Add-Member -InputObject $TestStatistics -MemberType NoteProperty -Name Distro -Value $Distro -Force
	Add-Member -InputObject $TestStatistics -MemberType NoteProperty -Name Installed -Value $ntpInstalled -Force
	Add-Member -InputObject $TestStatistics -MemberType NoteProperty -Name NTPVersion -Value $NTPVersion -Force
	return $TestStatistics
}

$distros = ($currentTestData.SubtestValues).Split(",")
foreach ($distro in $distros)
{
	try
	{
		$Global:detectedDistro = ""
		$result = ""
		$testResult = ""
		$isDeployed = ""
		$TestStatistics = CreateTestResultObject
		$CurrentTestData.Publisher = $xmlConfig.config.Azure.Deployment.$distro.Publisher
		$CurrentTestData.Offer = $xmlConfig.config.Azure.Deployment.$distro.Offer
		$CurrentTestData.Sku = $xmlConfig.config.Azure.Deployment.$distro.Sku
		$CurrentTestData.Version = $xmlConfig.config.Azure.Deployment.$distro.Version
		LogMsg "Publisher: $($CurrentTestData.Publisher)"
		LogMsg "Offer:     $($CurrentTestData.Offer)"
		LogMsg "Sku:       $($CurrentTestData.Sku)"
		$newLogDir = $LogDir + "\$distro"
		if(!(test-path $newLogDir))
		{
			mkdir $newLogDir
		}
		$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
		if ($isDeployed)
		{
			$hs1VIP = $AllVMData.PublicIP
			$hs1vm1sshport = $AllVMData.SSHPort
			$hs1ServiceUrl = $AllVMData.URL
			$hs1vm1Dip = $AllVMData.InternalIP

			RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
			RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo

			LogMsg "Executing : $($currentTestData.testScript)"
			RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "$python_cmd $($currentTestData.testScript)" -runAsSudo
			RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mv Runtime.log $($currentTestData.testScript).log" -runAsSudo
			RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/ntpinfo.log,/home/$user/state.txt, /home/$user/Summary.log, /home/$user/$($currentTestData.testScript).log" -downloadTo $newLogDir -port $hs1vm1sshport -username $user -password $password
			$testResult = Get-Content $newLogDir\Summary.log
			$testStatus = Get-Content $newLogDir\state.txt
			LogMsg "Test result : $testResult"
			if ($testResult -eq "PASS")
			{
				$ntpInfo = Get-Content $newLogDir\ntpinfo.log
				$ntpInstalled = $ntpInfo.split(':')[0]
				$ntpVersion = $ntpInfo.split(':')[-1]		
				$TestStatistics.Distro = $distro
				$TestStatistics.Installed = $ntpInstalled
				$TestStatistics.NTPVersion = $ntpVersion
				$allTestStatistics += $TestStatistics
			}
			if ($testStatus -eq "TestCompleted")
			{
				LogMsg "Test Completed"
			}
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

	$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $distro -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName

	$result = GetFinalResultHeader -resultarr $resultArr
	#Clean up the setup
	DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed -ResourceGroups $isDeployed

}

Out-Host -InputObject $allTestStatistics

#Return the result and summery to the test suite script..
return $result,$resultSummary