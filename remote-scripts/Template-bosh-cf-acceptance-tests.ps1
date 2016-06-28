<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()

try
{

    $templateName = $currentTestData.testName
    $parameters = $currentTestData.parameters
    $location = $xmlConfig.config.Azure.General.Location
	$SharedNetworkResourceGroupName = "bosh-share-network"
	$Domains = @{'AzureCloud'='mscfonline.info';'AzureChinaCloud'='mscfonline.site'}
	$Environment = $parameters.environment
	$DomainName = $Domains.Environment
	
    $V13CPIURL = "https://bosh.io/d/github.com/cloudfoundry-incubator/bosh-azure-cpi-release?v=13"
    $V13CPIURL_mc = "https://cloudfoundry.blob.core.chinacloudapi.cn/releases/bosh-azure-cpi-release-13.tgz"
    $V13CPISHA1 = "5d1d5f62a30911d5e07285d3dfa0f1c4b41262b9"
	$CF_RELEASE_URL = "https://cloudfoundry.blob.core.chinacloudapi.cn/releases/cf-release-231-local.tgz"
    if(Test-Path .\azuredeploy.parameters.json)
    {
        Remove-Item .\azuredeploy.parameters.json
    }
	
    # update template parameter file 
    LogMsg 'update template parameter file'
    $paramJsonfile =  Get-Content ..\azure-quickstart-templates\bosh-setup\azuredeploy.parameters.json -Raw | ConvertFrom-Json
	
    $Jsonfile =  Get-Content ..\azure-quickstart-templates\bosh-setup\azuredeploy.json -Raw | ConvertFrom-Json
	# check CPI Version
	$CPIUrl = $Jsonfile.variables.environmentAzureCloud.boshAzureCPIReleaseUrl
	$CPIVersion = [int]$CPIUrl.Split('=')[1]
	# if the orginal CPI Verison is v12 or lower, update version to v13
	if($CPIVersion -lt 13)
	{
		$Jsonfile.variables.environmentAzureCloud.boshAzureCPIReleaseUrl = $V13CPIURL
		$Jsonfile.variables.environmentAzureCloud.boshAzureCPIReleaseSha1 = $V13CPISHA1
		$Jsonfile.variables.environmentAzureChinaCloud.boshAzureCPIReleaseUrl = $V13CPIURL_mc
		$Jsonfile.variables.environmentAzureChinaCloud.boshAzureCPIReleaseSha1 = $V13CPISHA1
		$Jsonfile.variables.environmentAzureChinaCloud.cfReleaseUrl = $CF_RELEASE_URL
		($Jsonfile | ConvertTo-Json  -Depth 10).Replace("\u0027","'") | Out-File ..\azure-quickstart-templates\bosh-setup\azuredeploy.json
	}
	
    $curtime = Get-Date
    $timestr = "-" + $curtime.Month + "-" +  $curtime.Day  + "-" + $curtime.Hour + "-" + $curtime.Minute + "-" + $curtime.Second
    $paramJsonfile.parameters.vmName.value = $parameters.vmName + $timestr
    $paramJsonfile.parameters.adminUsername.value = $parameters.adminUsername
    $paramJsonfile.parameters.sshKeyData.value = $parameters.sshKeyData
    $paramJsonfile.parameters.environment.value = $parameters.environment
    $paramJsonfile.parameters.tenantID.value = $parameters.tenantID
    $paramJsonfile.parameters.clientID.value = $parameters.clientID
    $paramJsonfile.parameters.clientSecret.value = $parameters.clientSecret
    $paramJsonfile.parameters.autoDeployBosh.value = $parameters.autoDeployBosh
    
    # save template parameter file
    $paramJsonfile | ConvertTo-Json | Out-File .\azuredeploy.parameters.json
	
    if(Test-Path .\azuredeploy.parameters.json)
    {
        LogMsg "successful save azuredeploy.parameters.json"
    }
    else
    {
        LogMsg "fail to save azuredeploy.parameters.json"
    }


    $isDeployed = CreateAllRGDeploymentsWithTempParameters -templateName $templateName -location $location -TemplateFile ..\azure-quickstart-templates\bosh-setup\azuredeploy.json  -TemplateParameterFile .\azuredeploy.parameters.json

    if ($isDeployed[0] -eq $True)
    {
		$dep_ssh_info = $(Get-AzureRmResourceGroupDeployment -ResourceGroupName $isDeployed[1]).outputs['sshDevBox'].Value.Split(' ')[1]
		$old_cfip = $(Get-AzureRmResourceGroupDeployment -ResourceGroupName $isDeployed[1]).outputs['cloudFoundryIP'].Value
		$new_cfip = (Get-AzureRmPublicIpAddress -ResourceGroupName $SharedNetworkResourceGroupName -Name devbox-cf).IpAddress
		LogMsg $dep_ssh_info
		# connect to the devbox then deploy cf
		$port = 22
		$sshKey = "cf_devbox_privatekey.ppk"
		$command = 'hostname'
		echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "$command"
		$testTasks = ("acceptance test","smoke test")
		foreach ($SetupType in $currentTestData.SubtestValues.split(","))
		{
			if($DeployedMultipleVMCF)
			{
				echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "echo yes | bosh delete deployment multiple-cf-on-azure"			
			}
			if($DeployedSingleVMCF)
			{
				echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "echo yes | bosh delete deployment single-vm-cf-on-azure"						
			}
			#update yml file
			echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sed -i '/type: vip$/a\  cloud_properties:\n    resource_group_name: $SharedNetworkResourceGroupName' example_manifests/$SetupType.yml"
			echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sed -i 's/$old_cfip/$new_cfip/g' example_manifests/$SetupType.yml"
			echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sed -i 's/$new_cfip.xip.io/$DomainName/g' example_manifests/$SetupType.yml"
			$out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./deploy_cloudfoundry.sh example_manifests/$SetupType.yml && echo cf_deploy_ok || echo cf_deploy_fail"
			$out | Out-File $LogDir\deploy-$SetupType.log -Encoding utf8
			if($SetupType -eq 'multiple-vm-cf')
			{
				$DeployedMultipleVMCF = $True
			}
			if($SetupType -eq 'single-vm-cf')
			{
				$DeployedSingleVMCF = $True
			}
			if ($out -match "cf_deploy_ok")
			{					
				LogMsg "deploy $SetupType successfully, start to run test"
				foreach($testTask in $testTasks)
				{
					LogMsg "Testing $SetupType : $testTask"
					$metaData = "CF: $SetupType ; TestSuit : $testTask"
					if($testTask -eq 'acceptance test')
					{
						if($parameters.environment -eq 'AzureCloud')
						{
							$out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh run errand acceptance_tests --keep-alive --download-logs --logs-dir /tmp/ && echo cat_test_pass || echo cat_test_fail"						
						}
						else
						{
							$out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh run errand acceptance-tests-internetless --keep-alive --download-logs --logs-dir /tmp && echo cat_test_pass || echo cat_test_fail"												
						}
						$out | Out-File $LogDir\$SetupType-AcceptanceTest.log -Encoding utf8
						if($out -match "cat_test_pass")
						{
							$testResult = "PASS"
						}
						else
						{
							$testResult = "FAIL"
							LogMsg "Acceptance Test failed, please check details from $LogDir\$SetupType-AcceptanceTest.log"
						}
					}
					else
					{
						$out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh run errand smoke_tests --keep-alive --download-logs --logs-dir /tmp/ && echo smoke_test_pass || echo smoke_test_fail"						
						$out | Out-File $LogDir\$SetupType-SmokeTest.log -Encoding utf8
						if($out -match "smoke_test_pass")
						{
							$testResult = "PASS"
						}
						else
						{
							$testResult = "FAIL"
							LogMsg "Smoke Test failed, please check details from $LogDir\$SetupType-SmokeTest.log"
						}
						
					}
					$resultArr += $testResult
					$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
				}
			}
			else
			{
				LogMsg "deploy $SetupType failed, please check details from $LogDir\deploy-$SetupType.log"
				$testResult = "FAIL"
				$resultArr += $testResult
				$resultSummary +=  CreateResultSummary -testResult $testResult -metaData "CF: $SetupType; TestSuit : acceptance test" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
				$resultSummary +=  CreateResultSummary -testResult $testResult -metaData "CF: $SetupType; TestSuit : smoke test" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
			}
		}
    }
    else
    {
        throw 'deploy resouces with error, please check.'
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
		$resultArr += $testResult
		$resultSummary += CreateResultSummary -testResult $testResult -metaData "" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
    }
	
}

$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed[1] -ResourceGroups $isDeployed[1]

#Return the result and summery to the test suite script..
return $result, $resultSummary
